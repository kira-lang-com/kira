# Conformers of a trait across units

Status: option C implemented (section 5). Describes the fix for `KLF-KIR-9002`
"declares `X_G<n>` differently in two units" and the `textOf` duplicate
seen when a program's units share a library. Owner: the definitions in
`definitions/semantics/construct-families.klfd` and `definitions/lowering/`.

## 1. The problem

A trait's bare name in a type position is an existential
(`subset.md`, "Traits and existential dispatch"). It compiles to an enum
with one case per conforming declaration, and the methods that dispatch on
the case are generated from that case list. Each unit of a program lowers
on its own, so each unit builds the case list from the conformers *its
syntax tree holds*:

- `construct-families.klfd` `joinFamilies` / `joinFamily` add a case for each
  instance the unit sees through the family (`seenThrough` over
  `constructIndex(tree.constructs)`). `tree.constructs` is the unit's own
  tree.
- A unit's tree holds its own sources plus the declarations of the packages
  it depends on (`loader.klfd` `loadPackage`; packages built apart are read
  without their bodies). It does not hold sibling units or packages that
  depend on it.

So two units of one program hold different case lists for the same
existential enum. The enum has the same name (`typeSuffix` is a stable hash
of the type key), and the cases differ. `Merged::add`
(`crates/klf-defsvc/src/drive.rs`) then refuses the merge, because
`TypeDeclaration::describes_same` compares `variants`.

Concrete instance (`harmony-v2`, probe `app`): `ApprovalGate` has
`GrantingGate` (harness, `harness/app/ToolBridge.kira:125`), `RefusingGate`
(agent, `agent/app/Tools/Run.kira:24`) and, in agent's tests,
`AlwaysGrant` (`agent/app/Tests/AgentTests.kira:10`). The harness unit and
the agent unit see different subsets. The `textOf` duplicate is the same
mechanism for test constructs: agent's and Network's old-style test code in
`app/Tests` is compiled into every unit that reads the package, so the same
`Test` construct is lowered twice with different bodies.

Two rules are involved:

- A conformer declared in a package is visible to the units that read that
  package. It cannot be visible to the package it extends, because the
  package it extends is built first. Extensibility such as harness's
  `GrantingGate` conforming to agent's `ApprovalGate` is required and stays.
- Dispatch and helper functions are per unit. Each one enumerates the
  variants (equality, hashing, ordering, tracing, value helpers, arms,
  ridl-surface; `definitions/lowering/*.klfd` iterate `variants`). So a
  union of variant lists at merge is not enough: those function bodies
  differ too, and the merge of functions refuses them.

Union at merge was considered and rejected for that reason. Variants are
dense indices (`Operation::EnumNew/EnumSwitch/EnumTake/EnumProject`, `u32`),
so remapping them at merge would also have to rewrite every helper body.

## 2. Options

**Option C: canonical program-wide case list (recommended).** The enum
keeps its representation. What changes is which conformers its cases list.

- A pre-pass before any unit is lowered collects the conformer set of every
  existential trait over all units of the program: the units that
  `programUnits` (`package/separate-packages.klfd`) returns. A conformer is
  a declaration whose conformance list names the trait, identified by the
  type key of the trait's declaration.
- Each unit reads the declaration skeletons (no bodies) of every program
  unit, as `separate` packages already are, so every conformer's struct and
  construct declarations are in every unit's tree. Declarations of the same
  type merge by `describes_same`.
- Each unit builds an existential's cases from the program-wide set, sorted
  by the conformer's type key (not by source order and not by the unit's
  view). Then the enum declaration, and every helper generated from it, is
  identical in every unit. `Merged::add` dedupes them by `describes_same`
  and `same_function_definition`.
- A conformer added in a third unit extends the set for every unit, because
  the pre-pass is over the whole program. Adding a conformer changes the
  enum in all units consistently; no unit can keep a stale list.

Open points for C:
- The pre-pass must parse every unit's tree once. Parsing is already done
  per unit in `lower_one`; the pre-pass moves the conformer scan ahead of the
  lowering loop in `drive.rs` `lower_units`. This is one more parse per unit,
  not one per use.
- A conformer's name in a unit's tree may differ by import alias. The
  conformer set must be keyed by type key, resolved in the declaring unit.
  This needs the declaring unit's resolution, so the pre-pass resolves
  conformance names in each unit's own scope.
- Test-only conformers: `app/Tests` of a package read as app code makes its
  conformers part of the program in non-test builds. Option C then keeps
  them in non-test builds. Migrating those tests to `tests/` (the testing
  design, `testing.md` section 3) removes them from non-test builds. That
  migration is a precondition for a clean non-test build of the Harmony
  program; it is independent of C.

**Option T: table-driven existentials.** The enum is replaced by a value
of a stable conformer id (`instanceSuffix` of the type key) and a payload,
and dispatch goes through the conformance table. The tables are already
unioned at merge (`Merged::add` extends `witnesses`, `vtables`,
`conformances`). Helper functions then depend only on the trait declaration,
so they are identical in every unit.

T removes the per-unit case lists and needs no pre-pass. It changes the
runtime representation of every existential (`is`, `as`, `switch`, equality,
hashing, tracing), so it is a larger language and runtime change than C. Keep
T as the follow-up if C proves too costly to keep consistent.

## 3. Plan for C in steps

Each step lands with a regression test and its own signed commit. The tests
live beside the definitions they exercise (`languages/kira/tests`), and
multi-unit cases are fixture programs under `languages/kira/tests/conformers/`.

1. Conformer scan. A pre-pass over `programUnits` that returns the
   conformer set (trait key, conformer key, unit). Test: a two-unit program
   with partial conformers in each unit reports the union.
2. Declaration skeletons of sibling units. `loader.klfd` reads the
   skeletons of program units that are not already loaded. Test: a conformer
   declared in a sibling unit resolves its payload type in another unit.
3. Canonical cases. `joinFamily` builds the case list from the program-wide
   set in type-key order. Test: partial conformers in each unit produce
   identical enum declarations in both units, and `kira check` passes with no
   9002.
4. Stability. Test: a conformer added in a third unit changes the enum in
   every unit to the same declaration; the program's merged module does not
   depend on unit order.
5. Re-verify: `harmony-v2` app, harness, server and tests in default and
   `--test` builds; the `textOf` duplicate is resolved by the test migration
   (step outside this document).

## 4. Not changed by this document

- `subset.md` still describes one case per conforming declaration. That
  statement holds for C: the cases are the program's conformers. Update
  `subset.md` in step 3.
- No code changes accompany this document. The `KLF-KIR-9002` diagnostic
  stays: it still catches real conflicts between units.

## 5. Status and the naming rule

Done: the program's file list reaches every unit's parse (the parse phase
argument, `DefinitionPhaseArguments::Parse { unit, program }`); each unit
reads as declarations the packages of the program related to its own: those
it depends on, and every package that depends on one of those, its consumers
(`loadProgramPackages`, `relatedPackages`). A trait's conformers live in its
package's consumers, so every unit that sees the trait builds its existential
from the same conformers. A package related only through a bundled library is
another program's and is not read, and a bundled library's own unit reads no
consumers, since every program is one; every package of the program is still
marked apart, so one a related package imports is never compiled here; trait case lists
are kept in name order (`withCase`, `withVariant`); the fixtures under
`tests/conformers/` (Gate, Grant, Refuse, App) are the regression set, and
`App` exits 1.

A consumer read as declarations carries `extend` blocks on this unit's own
types. Their bodies are skipped by the parser, so each such method is marked
`extendedElsewhere` and is apart (`apartFunctions`): its own unit checks and
lowers it, and this one never reports it for a missing return.

The naming rule: a package built apart spells every type it declares
`Name#Module` in every unit, its own unit included. In a split build every
unit's own package is read apart by the program's other units, so the unit's
module 0 is named apart too (`Loader.readApart`); only a bundled package keeps
its plain spelling. A spelling therefore never depends on which packages one
unit happens to see. The earlier rule, that a name exactly one module of a
unit declares keeps its plain name, broke that: two units that each saw one
`ToolCall` both kept the plain name, and their declarations clashed at the
merge (KLF-KIR-9002). A trait no type of a unit conforms to is declared under a
name of that unit's own, whatever its spelling.

`@Main` is checked only for the packages a unit compiles: a package read
apart has its entry checked by its own unit.
