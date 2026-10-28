# Kira in KLFD: status and roadmap

This roadmap tracks the Kira reimplementation in this repository. The reference
is `../kira`; the controlling KLF design is section 27 of
`../kira-language-framework/roadmap/KLF-RIDL.md`. The KLF milestone exit test
for Kira is M7: parity with `tests-kik` and successful Kira ecosystem builds.

## Architecture

Kira is split into three layers, following KLF-RIDL section 27.2:

1. **Core** is this repository's `.klfd` definition. `definitions/` owns the
   lexer, parser, semantic analysis, lowering, diagnostics and package loading.
   It defines the language and lowers checked programs to shared KIR. Changes
   to language syntax or semantics belong here.
2. **Heap** is Kira source under `std/`. It owns allocation, reference counting,
   copy-on-write buffers and destruction, implemented using shared KIR/runtime
   services. It must not add Kira-specific VM or backend behavior.
3. **Std** is Kira source under `std/`, layered over core and heap. It owns the
   public language items and APIs, including `String`, `Array`, `Optional`,
   `Result`, `Drop`, `Copyable`, `Number` and `Any`.

Within KIR, owned/borrowed parameters use the RIDL calling conventions; structs
and enums use the common aggregate representation; arrays wrap counted buffer
references and use copy-on-write; dropping types use scoped destruction; and
generics specialize through the shared KIR pipeline. These are requirements
from section 27.3, not permission to add language-specific backend shortcuts.

## Current status

### Working

- `definitions/language.klfd` declares the `Kira` language profile and its
  parse, elaborate and lower phases. The package loader handles one package
  manifest, app modules, per-file imports and recursive path dependencies.
- The current executable subset supports integer widths and conversions,
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
  has a VM/native proof returning 5. Collector expansion remains unfinished.
- Quoted syntax has a focused VM/native proof returning 42, including identifier
  and integer splices, escaped strings and newline-separated syntax arrays.
  `Syntax` and `Identifier` values are ordinary Foundation source types.
- Diagnostics have Kira spelling and phase mappings in
  `docs/diagnostics.md`; `docs/subset.md` records accepted syntax and rejected
  constructs.
- The last full baseline passed 46 cases. Work since then is checked through
  focused corpora: arrays (3), heap (1), constructs (1), strings (1), floats
  (1), Any (1), and the unchanged original aliases section (1, checksum 161).
  These focused runs pass; there has been no new full-corpus run.
- `tests/app` holds this language's own suite, run by the compiler built here:
  `kira test tests` runs 1,611 cases through Kira's test protocol and they all
  pass (`1611 passed, 0 failed, 0 skipped, 1611 total`, exit 0).
  `tests/README.md` says how to run it and what the other two suites are.
- `tools/` holds the version manager: `knvm` installs a toolchain into
  `~/.klf/toolchains/<channel>/<version>/`, selects it, pins one per directory
  tree, and the launcher dispatches the `kira` on PATH to the selected
  toolchain's driver. It is `../kira/crates/kira-knvm` ported to Kira and pointed
  at this compiler; `tools/knvm/README.md` has the layout, the verbs and where it
  stops. `languages/kira/corpus/packages/knvm` checks the decisions it rests on, and the install,
  `binstall` and `sinstall` paths have been run end to end against a fixture feed
  and this checkout.

### Not implemented or not yet proven

- `T?`, `Drop`, `Copyable`, `Number`, complete lexical destruction and full
  ownership analysis remain unfinished. Owned header layouts are implemented;
  borrowed/exported RIDL ABI parity is not yet proven.
- Generic functions, generic methods, and nested generic type declarations are
  not fully supported. Traits remain unfinished. Classes, closures and async
  tasks pass every harness case that uses them.
- Compile-time function coverage beyond constant scalars and strings remains
  unfinished; the harness's derive and collector macros expand. KLF-RIDL
  section 14.4 requires execution of KIR in a VM with no host capabilities or
  foreign calls, a private bounded heap and a step budget. Runtime execution
  of a `comptime` call does not meet that requirement.
- Source-level `kira test` is distinct from `klf test`, and it works: the
  `Test` family is ordinary library source, a whole-program collector macro
  generates `kiraTestMain`, and the CLI runs that entrypoint. `kira test tests`
  runs the harness's 1611 cases through it.
- Registry and git dependencies, `@Export`, and broad `tests-kik`/ecosystem
  parity remain unimplemented or unverified.
- No release of this compiler is published, so the release half of `knvm` has
  never run against a live feed: `install latest` and `list --remote` are proven
  only against a local `KNVM_KIRA_RELEASE_DIR` fixture. `install-llvm`,
  `install libffi` and `self-update` are not ported — the first two provision
  what belongs to the framework, and `sinstall` already covers the third.

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

- Extend generic support from direct enum payloads and struct fields to nested
  generic types, generic methods and functions, using checked specialization
  to concrete KIR.
- Expand the implemented Array/String/Any verticals to all harness cases,
  including ownership diagnostics and borrowed/exported RIDL conventions.
- Extend static construct inheritance to full construct behavior and add
  whole-program collector expansion. Keep test discovery generic over the
  declared construct, rather than naming Test in the compiler.
- Add test build mode and the generated `kiraTestMain` contract, then exercise
  it through the `kira test` command across supported backends. Preserve the
  reference behavior for empty suites, suites with `@Main`, and test failures.

### 3. Build the heap layer

- Establish the `std/` source layout and package boundaries before adding public
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

- Use `../kira/tests-kik` as the conformance oracle. Compare acceptance,
  diagnostics, output and exit status on the supported backends.
- Build the Kira ecosystem packages against this compiler and its bundled std.
- Update this roadmap and the sibling KLF `roadmap/IMPLEMENTED.md` whenever a
  milestone is demonstrated. M7 is complete only when both tests-kik parity and
  ecosystem builds pass; the 46-case local corpus alone is not that gate.

## The `tests-kik` oracle

`kira test ../kira/tests-kik/harness` is **1544 passed, 0 failed**.

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
