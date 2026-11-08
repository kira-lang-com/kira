# Kira in KLFD: status and roadmap

This roadmap tracks the Kira reimplementation in this repository. The reference
is `../deprecated-kira-rust`; the controlling KLF design is section 27 of
`../kira-language-framework/roadmap/KLF-RIDL.md`. The KLF milestone exit test
for Kira is M7: parity with `tests-kik` and successful Kira ecosystem builds.

## Architecture

Kira is split into three layers, following KLF-RIDL section 27.2:

1. **Core** is this repository's `.kcore` definitions. `languages/kira/definitions/` owns the
   lexer, parser, semantic analysis, lowering, diagnostics and package loading.
   It defines the language and lowers checked programs to shared KIR. Changes
   to language syntax or semantics belong here.
2. **Heap** is Kira source under `languages/kira/std/`. It owns allocation, reference counting,
   copy-on-write buffers and destruction, implemented using shared KIR/runtime
   services. It must not add Kira-specific VM or backend behavior.
3. **Std** is Kira source under `languages/kira/std/`, layered over core and heap. It owns the
   public language items and APIs, including `String`, `Array`, `Optional`,
   `Result`, `Drop`, `Copyable`, `Number` and `Any`.

Within KIR, owned/borrowed parameters use the RIDL calling conventions; structs
and enums use the common aggregate representation; arrays wrap counted buffer
references and use copy-on-write; dropping types use scoped destruction; and
generics specialize through the shared KIR pipeline. These are requirements
from section 27.3, not permission to add language-specific backend shortcuts.

## Current status

### Working

- `languages/kira/definitions/language.kcore` declares the `Kira` language profile and its
  parse, elaborate and lower phases. The package loader handles one package
  manifest, app modules, per-file imports and recursive path dependencies.
- The compiler supports integer widths and conversions,
  booleans, functions and recursion, conditionals and loops, structs and
  methods, enums and exhaustive `match`, checked arithmetic and runtime traps.
- Generic enums and structs with direct type-parameter payloads or fields are
  specialized into concrete KIR types. `Optional<T>`, `Result<T, E>` and
  `Box<T>` compile from Kira source, including through imported packages.
- `std/Heap` provides typed byte/word access, offsets, counted buffers,
  retain/release, cloning and resizing in ordinary Kira source.
- Foundation declares `Optional`, `Result`, `Array`, `String` and `Any`.
  Arrays and strings use four-word owned headers and a static `BufferOps`
  table; array mutation detaches shared buffers. Managed locals and temporaries
  are cleaned up at function exits.
- Array indexing, append, array iteration, nested arrays, alias chains,
  labelled memberwise struct construction, static construct inheritance and
  required-method overrides are executable.
- Float arithmetic/conversions and erased `Any` values work in focused cases.
  `Any` compares nominal identity and structural values, and supports `is`/`as`.
  Typed equality/destruction helpers avoid recursively expanding helper bodies.
- The shared KLF VM now exposes `evaluate_module`, `Machine::for_evaluation`
  and `EvaluationBudget`. Evaluation uses a private heap, counts backing
  storage against the memory limit, shares a step budget across initializers
  and the entry, and denies foreign calls before host symbol resolution.
  One focused VM test passes for looping, denied foreign calls and oversized
  allocation. Kira now marks compile-time functions through the generic KIR
  builder services. A focused source package returns 118 on VM and native,
  covering constant integer calls, loops, nested calls and string branches.
  Runtime callers contain constants and owned string buffers, not comptime calls.
- Declarative expression and statement macros have a focused VM/native proof
  returning 164 for nesting, renamed locals and single evaluation of arguments.
  `place` parameters currently accept bare names. Procedural function macros
  have a VM/native proof returning 94. Derive reflection over structs, enums
  and distincts, with Foundation Equatable, Clone, Hashable and Ordered source
  macros, plus a Serializable distinct round trip with exact tagged wire text,
  has a VM/native proof returning 5. Whole-program collector expansion is
  also exercised by the source-level test runner; broader parity remains to be checked.
- Quoted syntax has a focused VM/native proof returning 42, including identifier
  and integer splices, escaped strings and newline-separated syntax arrays.
  `Syntax` and `Identifier` values are ordinary Foundation source types.
- Diagnostics have Kira spelling and phase mappings in
  `docs/diagnostics.md`; `docs/subset.md` records accepted syntax and rejected
  constructs.
- Historical corpus baseline: 46 cases, followed by focused corpora for
  arrays, heap, constructs, strings, floats, Any and aliases. This is a
  historical measurement, not the current full-corpus pass count; see
  `HANDOFF.md` for later run status and framework blockers.
- `tests/app` holds this language's own suite, run by the compiler built here:
  `kira test tests` runs 1,611 cases through Kira's test protocol and they all
  pass (`1611 passed, 0 failed, 0 skipped, 1611 total`, exit 0).
  `tests/README.md` says how to run it and what the other two suites are.
- `tools/` holds the version manager: `knvm` installs a toolchain into
  `~/.klf/toolchains/<channel>/<version>/`, selects it, pins one per directory
  tree, and the launcher dispatches the `kira` on PATH to the selected
  toolchain's driver. It is `../deprecated-kira-rust/crates/kira-knvm` ported to Kira and pointed
  at this compiler; `tools/knvm/README.md` has the layout, the verbs and where it
  stops. `languages/kira/corpus/packages/knvm` checks the decisions it rests on, and the install,
  `binstall` and `sinstall` paths have been run end to end against a fixture feed
  and this checkout.

### Remaining limitations and parity work

The items below distinguish a documented restriction from an unverified
reference-compiler compatibility claim. The newer `HANDOFF.md` and
`languages/kira/docs/subset.md` describe capabilities added since some early
roadmap milestones; do not treat those historical milestones as a current
missing-feature inventory.

- **Implemented, parity unverified:** `unsafe function` and `unsafe { ... }`
  are parsed and semantically checked, with diagnostic 3410 for unsafe
  operations outside a permitted boundary. This includes foreign-pointer and
  selected native-state operations. The Rust reference's `KSEM400` is a
  different diagnostic; exhaustive direct/indirect-call and boundary parity
  has not been demonstrated.
- **Implemented with restrictions:** generic functions and methods, traits,
  classes, closures, async tasks, derive macros, collectors, serialization
  examples, ownership checks and destruction lowering all have implementation
  paths. They must not be listed as wholly absent. Specific restrictions are
  tracked in `languages/kira/docs/subset.md`, including mutable-borrow
  captures, certain task bodies, macro parameter forms, and compile-time
  aggregate results. Complete lexical destruction and borrowed/exported RIDL
  ABI parity still require cross-backend verification.
- **Documented limitations:** dotted `import A.B` syntax is not accepted;
  registry and Git dependency declarations can be parsed, but automatic
  checkout/fetch is not supplied by the package loader (external checkouts
  are required). Do not conflate manifest parsing with fetching support.
- **Not yet established:** full reference `tests-kik` equivalence, diagnostics
  and runtime behavior across supported backends, full ecosystem builds,
  and `@Export` annotation compatibility. The 1,611 passing source-level tests
  and the documented 1,544 passing adjusted oracle are useful evidence, but
  neither by itself proves unrestricted compatibility.
- **Distribution:** no release of this compiler is published, so the release
  half of `knvm` has not been exercised against a live feed. `install latest`
  and `list --remote` were tested against a local fixture;
  `install-llvm`, `install libffi` and `self-update` are not ported.

## Work plan

### 1. Keep the compiler corpus reliable

- Keep the focused corpus runnable with `klf test ../klf-kira` from the KLF
  checkout (or `klf test .` from this repository).
- Add a focused corpus case whenever a language feature or diagnostic is
  implemented. Keep `docs/subset.md` and `docs/diagnostics.md` aligned with
  behavior.
- Treat this harness as compiler-definition conformance. Do not call it
  source-level `kira test`.

### 2. Complete the language mechanisms needed by std and tests

- Extend and verify existing generic type, method and function support against
  reference cases, including nested specializations and diagnostics.
- Expand the implemented Array/String/Any verticals to all harness cases,
  including ownership diagnostics and borrowed/exported RIDL conventions.
- Verify construct inheritance and existing whole-program collector expansion
  against reference cases. Keep test discovery generic over the declared
  construct, rather than naming Test in the compiler.
- Extend the implemented `kira test` / `kiraTestMain` contract across supported
  backends; check reference behavior for empty suites, suites with `@Main`,
  and test failures.

### 3. Build the heap layer

- Establish the `languages/kira/std/` source layout and package boundaries before adding public
  APIs.
- Expand the working counted buffer primitives to complete scoped destruction,
  task-safe lifetime behavior and all target alignments.
- Test ownership, retain/release balance, mutation of shared buffers, and
  destruction on each supported backend.

### 4. Build the public std layer

- Complete `Drop`, `Copyable` and `Number`, and extend the existing Array,
  String, Any, Optional and Result implementations against the harness.
- Match section 27.3's layouts and policies, including the four-word RIDL
  string, copy-on-write arrays and scoped destruction. Keep higher-level APIs
  in ordinary Kira source.
- Grow the standard API from the reference Foundation and keep platform APIs
  outside the portable core where appropriate.

### 5. Reach the Kira M7 exit test

- Use `../deprecated-kira-rust/tests-kik` as the conformance oracle. Compare acceptance,
  diagnostics, output and exit status on the supported backends.
- Build the Kira ecosystem packages against this compiler and its bundled std.
- Update this roadmap and the sibling KLF `roadmap/IMPLEMENTED.md` whenever a
  milestone is demonstrated. M7 is complete only when both tests-kik parity and
  ecosystem builds pass; the 46-case local corpus alone is not that gate.

## The `tests-kik` oracle

`kira test ../deprecated-kira-rust/tests-kik/harness` is **1544 passed, 0 failed**.

Two adjustments were made to the oracle, both the kind this repository has
already made to it (the colon result headers became arrows when the harness
was copied in):

- `Foundation.printLine` is gone. The reference's Foundation defines it as
  `print` under another name, so the four `TestRunner` collectors call `print`
  directly. It mattered more than a rename: the collector generates every test
  entry point, so one undefined name in it left the whole generated runner
  unresolvable — 1545 diagnostics at once.
- `FoundationPerspectiveAndLookAt` expects `4`. The perspective scale is
  `1 / tan(π/4)`, exactly one in decimal and a shade under one in binary
  floating point, and the oracle's old expectation of `2` measured that
  rounding. This compiler computes the matrix in decimal, so the scale is one
  and the sum is four.

## Immediate next slice

All 1,511 copied harness cases pass through `kira test tests`. Keep them passing,
and never substitute the old compiler binary for the KLFD implementation. Next
are module-scoped type namespaces (the three failing corpus cases), implicit
Foundation for a lone file, and memory on large builds.
