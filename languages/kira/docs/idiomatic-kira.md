# Idiomatic Kira

Kira code should express its domain, make failure visible, and keep binary details
at a boundary. `kira check` reports style warnings as well as type errors.

## Types describe meaning

- Use `Number` for quantities: amounts, sizes, durations, coordinates and rates.
  Literals infer `Number` when Foundation is available. An explicit parameter or
  annotation still supplies the required numeric type.
- Use `Int` for collection positions and machine words. Fixed-width integers and
  raw pointers belong in the layer talking to C, a kernel, hardware or a wire
  format. Convert there, not throughout program logic.
- Kinds, states, operations, keys and reasons are enums, not integer codes.
  Decode once at the input boundary. Use explicit enum raw values for fixed codes.
- An extensible code set is an `@Open` enum with raw values,
  `@Open enum Key: U32 { Escape = 41 F12 = 69 }`: the known codes are cases,
  and an unknown code survives `fromCode` and `code` unchanged.
- IDs are distinct types. A surface ID must not pass as a window ID.
- Flags are distinct integer types with named constants. Combine them with `|`,
  intersect them with `&`, and test membership with `.has(...)`.
- Absence is `T?` or `Optional<T>`, never an empty string, negative index or zero
  handle. Do not pair a value with an `ok: Bool` field.
- Messages are enums whose payloads have named fields, not structs of `a`, `b`,
  `c` and an integer opcode. Strings are input, not internal dispatch types.
- Name non-obvious constants once, in the package owning their meaning.
- A Boolean describes truth. It should not select two different behaviours;
  use an enum or two functions instead.

## Failures are values that must be handled

A fallible operation returns `Result<Value, Failure>`. Success without a value
is `Result<Void, Failure>` with `.Ok`. Failure enums name specific reasons rather
than a generic status number or a lone `Failed(String)`.

At a call site, propagate with `try`, match and handle the failure, choose an
explicit fallback with `otherwise`, or use `absorb` with a comment saying why
discarding the failure is correct. Never drop a `Result`, bind it to `_`, or put
a status code inside `.Ok`. Do not turn a failure into an invented empty value.

`otherwise` takes an optional value too: `try cache.lookup(key) otherwise
return .None` is the value `Some` holds, or the fallback for `None`.

```kira
let contents = try readFile(path) otherwise return .Error(.MissingConfiguration)
match writeFile(path, contents.text) {
    Ok -> {}
    Error(failure) -> log warn("could not save configuration", path, failure)
}
```

## State and structure

- Create mutable state at the entry point. Keep it in structs and pass it with
  `borrow mut`; do not create top-level mutable registries or counters. A
  framework is the exception: its calls come through RIDL with no context, so
  its process state is one top-level `var`, and 6001 is not reported when it
  is built with `--emit shared` or `--emit ridl`.
- Put operations on the type they act on. Packages are already namespaces;
  avoid short prefixes on free functions and globals.
- Export only the declarations callers need. Implementation helpers stay private.
- Shared helpers live once in a shared library. Prefer Foundation and builtins
  to hand-written text, math, file, hashing and memory helpers.
- Raw allocation, memory access and binary layout live in one boundary layer.
  Above it, use typed structs and enums.
- Keep functions around 40 lines and files below 700 lines. Split long match
  arms into functions; replace long parameter lists with a request struct.
- Constants are namespaced `let` declarations, not zero-argument functions.
- A function returning nothing has no trailing `return`; retain early returns.
- `@Native` is not a Kira annotation. Foreign declarations use `@FFI.*`.
- Name what an operation answers or does, not vague steps such as `handle` or
  `process`. Use full words instead of shortened variable names.

## Control flow

- List every case when matching an enum your package owns. A fallback is for
  strings, integers, unknown external values and enums another package owns.
- Use `match` instead of repeated equality tests over the same value.
- Use `for` ranges rather than counted `while` loops. Iterate elements directly;
  use `for (index, value) in values.enumerated()` when both are needed.
- Search with `contains` or a function returning an optional value, not flags
  assigned inside a loop.
- Use `while true` with `break` or `return`, not a mutable running flag.
- Wait for an event when the platform offers one. If polling is unavoidable,
  name its interval and explain why polling is required.
- Use leading-dot enum cases wherever context supplies the type.
- An intentionally empty arm needs a comment saying why nothing happens.

## Input, output and comments

`print` is a program's output to its user. `log` is for diagnostics and carries
typed fields directly, including `Number`. Use interpolation for readable text
instead of chains of conversions and concatenations.

A `log` belongs to a category: a case of a `LogCategory` enum declared by the
package that owns the code (`log(category: Tls.Handshake, "peer accepted", peer)`),
or the module's implicit one when the statement names none. Turn categories on
with `KIRA_LOG` or `Log.enable` when you debug, and leave the statement in
place. No probe, smoke-test code or temporary `print` may be committed: if you
need to see a value, log it to a category and enable that category. See
`logging.md`.

Command lines use the `ArgumentParser` package (`kira-projects/argument-parser`,
a path dependency): declare a command and its schema, derive `Parsable` for typed
arguments, and call `runCommand` with `commandLineArguments()`. Do not decode
process arguments by hand.

Comments split by what they say. A `//` comment explains why: a decision, a
constraint, or a consequence the code cannot show. A `///` doc comment states
the contract of the declaration below it: what it is for, what it takes, what
it returns and how it fails. A `//!` comment at the top of a file says what the
file is for. A comment never restates the code; delete one that does, and
delete dead code, copied helpers and placeholder functions that report success
without doing any work. Public API carries `///` (docs/documentation.md).

## Packages and checks

Write manifests as constructs extending `Package`, with typed members. Both
manifest spellings reject unknown members, but the construct form is the
documented form.

Before handing back a package:

```sh
kira check .
kira test .
kira format --check .
```

Review raw pointers, integer-width conversions, dropped results, top-level state,
prefixed names, counted loops and enum fallbacks. A clean type check is not an
excuse to ignore a style warning or conceal a failure.
