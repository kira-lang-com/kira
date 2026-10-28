# Handoff

This is Kira hosted on the Kira Language Framework: the Kira compiler written as `.klfd` definitions (KLF-RIDL section 27).

## Ground rules

- **Syntax and semantics reference:** `../kira`, the Rust implementation, and its `sites/docs`. For example, integer widths trap at the written width, conversions are written `I32(x)`, and `Int` pairs with any width.
- **Design reference:** `../karc`.
- **Quality bar:** code that reads cleanly, is idiomatic, has a clean API shape and sits in organized folders.
- **Framework rules:** `../kira-language-framework/AGENTS.md`. No subagents, few cargo runs, a 700-line cap per file, signed commits on `main`, and no AI trailers.

## Layout

- `definitions/language.klfd`: the `Kira` construct, the `DiagnosticSpec` list, and the four phases. `parse` produces a `SyntaxTree` artifact, `elaborate` produces a `CheckedProgram` artifact, and `lower` produces KIR.
- `definitions/diagnostics.klfd`: the `Diagnostic` enum and its `code()`. Kira's code families become number bands: KLEX is 1xxx, KPAR is 2xxx, KSEM is 3xxx, and 9001 means outside the subset.
- `definitions/syntax/`: token, lexer, tree, parser (the cursor), declarations, statements, expressions. It fails at the first error.
- `definitions/semantics/`: types, program (the checked IR), declarations, checker, statements, expressions, calls. It reports every error and poisons the failed expression with `Invalid`.
- `definitions/lowering/`: kir (the only file that calls `klf.kir.*`, as methods on handles), types, module, function, values, operations.

## Status

- **Kira's own harness passes 1611/1611:** `kira test tests` prints `1611 passed, 0 failed, 0 skipped, 1611 total` and exits 0 in about 8 s. `kira` is the native frontend that `klf build .` produces. `kira test` and `kira run` are `compatDriver` subcommands for `--test --emit run` and `--emit run` (`definitions/driver/`); the `runProgram` hook drives the test binary through Kira's protocol (`list`, `expect`, `check`, `body`), one child process per step (framework D-323, D-324). Building a binary from a workspace frontend runs `cargo` for the runtime, so `~/.cargo/bin` must be on `PATH` unless `KLF_HOME` names an installed kernel.
- **The corpus (`klf test .`) does not run at the moment (2026-10-12).** Its sysroot step compiles the std as loose files (framework section 5.3). `units` now makes one unit per std package that no other std package depends on, so that step gets past 4001. It then stops in `--emit lib` of Foundation: the value helpers `Inflater#1500058`, `Inflater#1550058` and `Inflater#100058` all mangle to `_RIDL14kira8InflaterF`, because `klf-ridl` `mangle::component` drops everything from `#` on. Until then, run a corpus package directly with `kira build <package> -o out`. The count was 149 of 149 before this. Each module has its own type namespace, as in kira (`definitions/semantics/namespaces.klfd`, `namespace-rewrite.klfd`): before checking, a type name more than one module declares is kept by the first library that declares it, every other declaration becomes `Name#module`, and each reference is rewritten to the declaration its file sees (own module, then imports in order; `Library.Name` through the import). Renamed types get a KIR suffix, and descriptors show the written name.
- **Compile time:** the harness build (about 1 MB of source plus 3.6 MB of generated runner) takes 5.6 s cold and 4.4 s warm, against kira's 207 s. It peaks at 1.2 GB cold and 0.8 GB warm, against kira's 174 MB. Cranelift reuses machine code from the previous build of the same output (`~/.cache/klf/cranelift`, or `$KLF_CACHE`; `klf clean` removes it). Natively, array and string buffers that nothing reaches are collected (framework D-321).
- **FFI:** every `.klffi` form of framework section 26 compiles (framework D-326): externs with `retains:`, variadic calls, addresses, Linux system calls (aarch64 and x86_64), C structs and unions with bit-fields, borrowed, unmanaged and owned pointers (an owned one is moved, never copied: 3378), arrays, aliases, and callbacks from functions and lambdas, a capturing lambda through the callback's `context:` parameter. A package's `NativeLibrary` names its `binary`, `header`, `klffi` and `linkerFlags`. `klf test . --corpus ffi` runs 25 programs against C archives, and `--corpus ffi-diagnostics` checks every FFI code at its line. `klf ffi gen` (generating a `.klffi` from a header) is not done: it needs the C definition's parser.
- **The trail (logging):** `log` statements, `try … otherwise`, `absorb`, `handle` arms and `return .Error(…)` record events on Foundation's trail (`std/Foundation/app/Trail.kira`, rendered by `TrailReport.kira` as compiler-style reports with source excerpts and the chain of sites a failure came through). The parser writes them (`definitions/syntax/log.klfd`, `failure-trail.klfd`); fields are shown through `traceText`, which lowering expands per type (`definitions/lowering/tracing.klfd`), or through a type's `Traced` conformance (`Trace.kira`). A `match` that discards a result's failure is refused (3394). `@AtExit` functions are registered by the entry, not a module initializer, so compile-time evaluation never reaches a kernel service.
- **Typed memory and the Heap library (2026-10-08):** `heapLoad<T>`, `heapStore<T>`, `sizeOf<T>`, `alignOf<T>`, `heapFillBytes` and `heapMoveBytes` read and write C-shaped values at their C layout (`definitions/semantics/heap.klfd`, `definitions/lowering/typed-memory.klfd`; 3396, 3397). A struct whose `drop` runs is never implicitly copied (3398, `semantics/owned-pointers.klfd`). `std/Heap` adds `MemoryLayout`, raw memory, `MemoryView`, `ByteBlock`, `Boxed<Value>` and `Arena` (`docs/subset.md`, "The Heap library"); corpus `heap-library` runs them all, and `KLF_HEAP_REPORT=1` shows they leave nothing behind. `heapMoveBytes` needs the framework's `klf.kir.value.mem_move` service, and storing a `Bool` needs its Cranelift fix for same-width conversions: install the newest framework (`knvm klf install latest`) before `knvm binstall` here. Not yet: atomics and volatile access (KIR has them; neither Cranelift nor the definition builder lowers them), and allocator internals (returning spans to the OS, threads). A raw free of a slot that is already free traps with `KLF-RT-0006` (framework `Heap::free_raw`).
- **Programs:** `main` returns the process exit status, and a trap exits with status 1 (the `ProcessExit` entry convention). Programs reach the OS only through `@Service klfsvc_*` kernel services, never libc, so the same lowering serves every platform runtime.
- **Docs:** `README.md`, `docs/subset.md` (what kira accepts, including foreign functions) and `docs/diagnostics.md` (every code, its Kira spelling and its phase). Both were rewritten against the installed definitions on 2026-10-06; `subset.md`'s type, statement and expression sections had predated strings, floats, arrays, classes, traits, generic functions, channels, `distinct`, `NativeState`, the bare heap builtins and `declaration.family`, and had listed five of its nine "outside the subset" items as capability limits when they were missing-import failures.
- **Scope across packages (2026-10-14), corpus `nearest-scope-wins` (packages.klfd):**
  - A bare call inside a method tries the sibling methods before any free function, unless the name is a type's (`checkCall`, `nearestOwner` in `semantics/calls.klfd`). An imported library's function no longer takes the call away from the method.
  - A generic method keeps its own type parameters wherever it ends up. This covers `extend` blocks, and a block on a construct family once it has joined the family's enum and struct (`typeParameterScopes` in `semantics/namespace-rewrite.klfd`). A generic method's signature is not collected as a concrete instance (`appendFunctionReferences` in `semantics/generics.klfd`). Before this, `Value` in `onChange<Value>` resolved to KiraDB's `Value` in any app that imported both.
  - A leading-dot argument (`.Case`, `.Case(payload)`) fits only a parameter whose enum declares that case (`variantFits` in `semantics/overloads.klfd`, used by `overloadScore` and `headerScore`). Before this, `HStack(spacing: .Length(4))` inside HStack's own `init(spacing: Number)` chose that init again, which reported 3119.
  - A `private` method is not exported to RIDL (`isPublic` in `semantics/checker.klfd`).
  - The framework's compile-time evaluation runs only the initializers a folded call needs (`needed_initializers` in `klf-defsvc/src/evaluation.rs`). Before this, KiraDB's `comptime function remainderTable` ran every module's initializer, KiraUI's native ones included, and trapped with `KLF-VM-0024`.
- **Next:**
  1. Implicit Foundation for a lone file, as in kira.
  2. Memory on large builds: the live KLFD data (`Expression` is 168 B, `TypedExpression` 128 B) and the Rust KIR module (2.2M instructions for the harness) dominate the peak.

## ksl, the shader definition

Paths below under `definitions/`, `std/`, `corpus/` and `tests/` are relative to `languages/kira/`. The `ksl` definition is Kira's and lives in `languages/ksl`; `knvm binstall` builds it beside kira from `toolchain.klfd`, or build it alone with `klf build languages/ksl -o ksl`.

- **`ksl!`:** expanding `ksl!("Shaders/X.ksl")` runs `ksl build` on that file into the package's `generated/shaders`, then embeds what it wrote (`definitions/syntax/ksl-artifacts.klfd`). A rejected shader is 4038, after ksl's own diagnostics. Without `ksl` on the path, an earlier build's files are read, and none at all is 4039. `ember`, `kira-ui`, `kira-layout`, `kcoreui`, `kcoreanimation`, `kira-code` and `kira-editor` all check clean with the installed `kira`. The `Package Name { }` manifest and `name: value` struct literals this note used to blame are both accepted now (`package/manifest.klfd:60`, `syntax/expressions.klfd:277-279`); what the examples still have to write is **commas between struct-literal fields**, which the parser requires and those sources omit — fix that and `ksl_triangle` checks clean. `kira-ipc` is the one package still failing: its derive macros name `String` and `Syntax` without importing Foundation (3050), and past that it needs explicit `move` at owned-parameter calls (3108) where the oracle inferred it.
- **The oracle:** `../kira/crates/kira-ksl-*` for the semantics and `kira-shader-ir/src/layout.rs` for packing. KSL's own corrections are listed in the README: enums are `Int`, and samples read level zero. Imports match each segment ignoring case, as the oracle does.

## Framework work done for this (`../kira-language-framework`, D-300 to D-307)

- **KLF Kira methods:** in struct and enum bodies and `extend`, including on kernel handle types. Supports `borrow self` and `borrow mut self`, bare member names, sibling calls, and static methods.
- **Top-level `let` constants:** literals only.
- **Generic enums:** monomorphized, with their methods. The prelude `Optional` has `isSome` and `isNone`, and `Result` is in the prelude too.
- **Enum payloads:** a case can carry several payloads, and aggregate payloads are allowed.
- **`try`:** a unary expression over Result-shaped enums.
- **`match` arms:** an arm may ignore the payload.
- **Line continuation:** a line that starts with a binary operator continues the previous line.
- **Comparisons:** a leading-dot case compared with `==` or `!=` takes its enum from the other operand.
- **Low-level enum services:** `klf.kir.type.enum`, `enum_named`, `enum_case`, `enum_inject`, `enum_payload_address`, `enum_tag` and `switch.enum`.
- **Kira test harness:** `crates/klf-driver/tests/kira/mod.rs`, which points at `../klf-kira/definitions` (now `../klf-kira/languages/kira/definitions`).

## KLF Kira constraints to keep in mind

- `match` has no wildcard arm. Put exhaustive predicates on the enum itself, as in `Operation.integer()` and `ExpressionKind.name()`.
- A leading-dot case with no type context is ambiguous when two enums share the case name. Annotate the binding.
- There are no closures and no list methods beyond `.append` and `.count`.
- The installed `klf` has no `Optional.unwrap()`. Absence is an `Optional` matched explicitly (module manifests, resolved imports, struct-literal fields, source lookups), never a `-1` sentinel or a fallback to the first source.
- A `.None` with no type context is ambiguous. Bind it to an annotated `let` first.
- A phase's top-level function names must not collide with the phases: the parser's entry point is `parseSource` rather than `parse`.
