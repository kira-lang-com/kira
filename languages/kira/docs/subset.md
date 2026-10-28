# The subset kira compiles

kira compiles a subset of Kira. Everything here follows the reference
implementation in `../kira`: a program kira accepts means the same thing there.
A construct outside the subset that the parser recognizes is rejected with
9001; anything else is a parse error.

The installed definition tree at
`~/.klf/toolchains/kira/dev/0.1.0/definitions/` is what decides any question
this document does not settle. Where this prose and those `.klfd` files
disagree, they are right and this is the bug.

## Programs and packages

- A package is a directory holding `package.kira` and an `app/` directory.
  `package.kira` declares the package as a construct extending `Package`
  (see below). A construct without arguments writes no parentheses.
  Every `.kira` file under `app/`, in any subdirectory, belongs to one module:
  the files see each other's declarations without importing anything.
- `kira` finds the package by walking up from the path it is given, so
  `kira shop`, `kira shop/app/main.kira` and any other file of the package
  compile the same program.
- A lone `.kira` file with no `package.kira` above it is a program of its own.
  Several files without a package are rejected (4001).
- Exactly one function of the program is marked `@Main`, and it takes no
  parameters. An `Int` result is printed as `RET <value>`. `@Main` on a
  struct or construct makes the entry for it, as Swift's `@main` does: the
  entry makes the type's value, `Name()` for a form and `Name {}` otherwise,
  and calls its `main()`. A package whose
  `kind` is `.Library` declares none (3255).
- A top-level `@AtExit function name(reason: Int, detail: Int)` runs as the
  program ends: `reason` is 0 after a return, 1 after a trap (`detail` is
  its `KLF-RT` number), 2 after a failure and 3 after a VM fault (3393).
  A library built on its own registers its `@AtExit` functions as it loads,
  since its `.ridl` contract carries no `@AtExit`; the program's run first,
  then each library's, the last loaded first.
- An annotation is `@Name` or `@Name(arguments)`, its arguments written as a
  call's; `@Name { ... }` is 9001. A built-in attribute takes what it
  declares: `@Derive(...)` the names of its macros, `@Service("...")` and
  `@Ridl("...")` one string, the `@FFI.*` forms their block, and any other
  nothing (9001).
- A built-in attribute applies where it is declared to. A function takes
  `@Main`, `@MainThread`, `@AtExit`, `@Runtime`, `@Export`, `@Required`,
  `@TypeTable`, `@Service`, `@Ridl` and `@FFI.*`; a field or member takes
  `@Required`, `@Content` and `@FFI.*`; a type declaration takes `@Open` on an
  enum, `@Main` on a struct or construct, `@FFI.*` and `@Derive(...)`. Written anywhere else it is 3403.
- Any other name names a macro or a property wrapper in scope, which takes
  the annotation up with its arguments. A name nothing takes up is 3402 on a
  function, field or member and 5001 on a type declaration.

## Libraries and `import`

`import Name` makes a library visible in the file that writes it, and
`import Name as Alias` names it `Alias` there. `Name` is the `moduleRoot` of a
dependency listed in `package.kira`:

```kira
construct Shop extends Package {
    let version: String = "0.1.0"
    let dependencies: [Dependency] = [
        Dependency { name: "Geometry", path: "../geometry" }
    ]
}
```

`Package` declares every member with its default, so a package writes only
what it changes: `kind` is `.App`, `moduleRoot` is the construct's own name,
`version` is empty, and `dependencies`, `nativeLibraries` and `assets` are
`[]`.

A name no dependency answers may name a package the toolchain bundles: the
std's `<stdRoot>/Name/package.kira` whose module root is `Name`. That is how
`import Foundation` resolves from a package that does not list it, and it is
the reason a program that has not imported Foundation has no `String` type at
all — and so no string literals (see "Outside the subset").

A name neither answers may name a framework of the SDK given with `--sdk
<path>` (KLF-RIDL section 27.7): `<sdk>/System/Library/Frameworks/Name.framework`,
else the same under `PrivateFrameworks`. Its `Resources/*.ridl` contract is
read in place as the module's declarations, and the program links the
framework's binary dynamically, finding it at run time where the SDK path
without its prefix says it is installed. The manifest names nothing for it.
A contract that cannot be read is 4044.

### Platform files

An import may name the platforms it is made on, as `Build.platform()` spells
them (KLF-RIDL section 27.8):

```kira
import AppKit on tessera
import Metal on macos, ios
```

A file holding one is a platform file. It takes part in its module only when
the build is for a platform every `on` clause in it names; for any other the
file is not read past its imports, so its declarations do not exist and its
imports need not resolve. Every import in it comes before its first
declaration (4046), and a name that is not a platform is 4045. Other files
reach a platform file's declarations through code a macro emits for that
platform alone, by `Build.platform()`.

A manifest makes its dependencies available to those imports; it does not
make an unused dependency a build unit. Dependency loading and split-package
planning both follow the imports of files active on the target. In particular,
a dependency imported only by an excluded platform file needs no source
checkout or host SDK, and none of its declarations is checked or compiled.

`Build.platform()` is `"tessera"` for `aarch64-unknown-tessera` and
`x86_64-unknown-tessera`, never `"linux"`, though Tessera runs on the Linux
kernel; Foundation's `targetPlatform!()` folds to `TargetPlatform.Tessera`.

### The manifest

`Package` declares every member with a default, so a package writes only what
it changes:

| Member | Type | Default |
| --- | --- | --- |
| `kind` | `PackageKind` (`.App` or `.Library`) | `.App` |
| `version` | `String` | `""` |
| `moduleRoot` | `String` | the construct's name |
| `dependencies` | `[Dependency]` | `[]` |
| `nativeLibraries` | `[NativeLibrary]` | `[]` |
| `assets` | `[String]` | `[]` |
| `kira` | `String` | not read |
| `packages` | `[String]` | not read |
| `allowThinFfiShim` | `Bool` | not read |
| `defaults` | `Defaults` | not read |

The last four are accepted at their written type and then discarded. So is
`defaults`, in every manifest in this ecosystem, including Kira's own
ecosystem packages: a `Defaults { ... }` member has never been load-bearing
here, and if it ever was, the symptom is an unexplained target rather than an
error.

A member `Package` does not declare is 4003 in the `construct` form, and one
written at another type is 4004. A `Dependency` takes `name` and one of `path`,
`version` (registry) or `url` with `rev` or `tag` (git).

There are two spellings. The `construct` form above writes each member's type,
and every package in this ecosystem is written in it. The older form leaves the
types out, and is still read so old manifests keep compiling:

```kira
Package Shop {
    let version = "0.1.0"
    let kind = PackageKind.App
}
```

Both compile, and both refuse a member kira does not recognise with 4003, so a
typo such as `dependancies` or `nativeLibrarys` is an error rather than a
package that silently declares nothing. The declared set is `kind`, `version`,
`moduleRoot`, `dependencies` and `nativeLibraries`, and a `NativeLibrary` takes
`name`, `binary`, `header`, `klffi`, `linkerFlags`, `linkMode`, `availability`,
`headers`, `sources`, `autobind` and `nativeTargets`.

- Only path dependencies resolve. A `version` (registry) or `url` (git)
  dependency is rejected (4028, 4029).
- A library is a package with `kind = .Library`. Its own dependencies load
  with it, once however many packages use them. A cycle is rejected (4021).
- Every declaration of the program shares one namespace, as in Kira: a name
  means the same thing in every file. A library's declarations may be named
  only in files that import it (3027); another file's import does not carry
  over.
- `Alias.function(...)` and `Alias.Type` name a declaration through the
  import; a bare name works as well.

## Types

- `Int` (64-bit, signed), `I8`, `I16`, `I32` (also `Int32`), `U8`, `U16`,
  `U32`, `U64`, `Bool`, `Void` and the opaque `RawPtr` heap address.
- `Float` and `F32`, with `+ - * /`, comparisons and `Int(x)` to narrow.
- `Number`, Foundation's exact decimal: a signed 65-bit mantissa, so every
  `Int` and every `U64`, and up to eighteen fractional digits. It takes
  `+ - * / %`, comparisons, and on whole numbers `& | ^ ~ << >>` as on a
  65-bit two's complement integer; a fraction there traps. A decimal literal
   infers `Number` when Foundation is available unless its position expects a
   different numeric type. A decimal literal past `Int`'s largest is still a
   `Number` up to the mantissa's reach, so `18446744073709551615` and
   `-18446744073709551616` are numbers; where a width is expected only `U64`
   holds one. Decimal arithmetic is exact, and a hexadecimal one names a `U64`'s
  bits, so `0xffffffffffffffff` is 18446744073709551615. `Number(x)` takes
  any integer, a `Float` or a `String`; `U64(n)`, `Int(n)` and the other
  widths truncate toward zero and trap outside the target, and
  `U32(Number(7))` with an integer literal inside folds to the literal. An
  `Int` is 64 bits and a `Number`'s mantissa is 65, so the two mix wherever a
  value is wanted and the integer widens without a rounding or a range that
  can be lost; which way round they are written does not matter. The narrowing
   the other way is range-checked and truncates toward zero when a declared
   integer parameter or position requires it. `UNumber` names the same type, for a value that is never negative
  to say so where it is declared, and is an alias until it is not.
  `N8`, `N16` and `N32` (signed) and `UN8`, `UN16` and `UN32` (never
  negative) are numbers whose values fit that many bits, such as a field of a
  wire record. Each is stored as a `Number` until the compiler gives it its
  own size, and is already a type of its own that converts one way only: it
  widens into any number that holds all its values (`UN8` into `UN32`, `N32`
  or `Number`), and so does an integer type it holds (`U32` into `UN32`).
  Narrowing loses range, so it is written as a conversion, `UN32(n)`. A
  literal must fit (`let x: UN8 = 300` is 3350), and arithmetic on two values
  of one sized type keeps that type.
- A loop bound and an array index may be a whole `Number`, taken as one the
  way `Int(n)` takes one, so `for index in 0..items.count` and
  `items[index]` are what they were and also read when the value came from a
  quantity. A negative literal is a decimal like any other, so
  `var owed: Number = -3` and `var owed: Number = -0.50` are what they look
  like.
- `String` and `Any`, both from Foundation, and `[T]`.
- `Map<Key, Value>` and `Set<Element>` from Foundation, copy-on-write like an
  array and iterated in the order their keys were first added (KLF section
  6.4). `Map<String, Number>()` is empty; `set`, `value` (an optional),
  `contains`, `remove` (the value it held), `removeAll`, `count()`, `keys()`,
  `values()` and `entries()` read and write it. A `Set` has `insert`,
  `contains`, `remove` (whether it held the element) and `elements()`.
  Replacing a value keeps its key in place; removing a key and adding it
  again moves it to the end. A key is anything `hash` and `==` take.
- Structs declared with `struct`, classes with `class`, enums with `enum`,
  distinct types with `distinct Name = Representation`, nominal aliases with
  `type Name = Target`.

Each integer spelling is its own type, so `U8` and `U16` do not mix. A literal
takes the width its position expects and must fit it. `Int` pairs with any
width, so a width can flow into an `Int` and back. Values cross between widths
through a conversion written as a call to the type: `I32(x)`, `U8(total)`,
`Int(byte)`. A conversion traps when the destination cannot hold the value.

A `distinct` type is built by calling it, `Metres(5)`, and its representation
reads back through `.raw`. It is a distinct type rather than an alias because
two of them over one representation stay apart.

### Classes

`class Name { ... }` declares a type with reference storage, and `var` fields
on it are written through the handle: `c.bump()` on a `borrow mut self` method
writes the caller's value. A `let` binding of a class value is immutable
(3021) — the handle is immutable, not the object. Handles are counted: a
copy retains the instance and a handle going away releases it. A class that
claims `Drop` runs its `drop` once, when the last handle goes, before its
fields are released; its `self` is that last handle.

### Traits and existential dispatch

`trait Name { ... }` declares members a conforming type promises. A member
without a body is a requirement (`@Required function ...`, or no annotation at
all inside a trait body); one with a body is a default the conforming type
inherits. `struct Name: Trait` conforms, and the compiler checks the
conformance at the use.

A trait's **bare name in a type position is the existential**:

```kira
trait Greeter {
    @Required function greeting() -> String
}

struct English: Greeter {
    let name: String
    function greeting() -> String { return "hello" }
}

function make() -> Greeter { return English { name: "a" } }
```

`Any Greeter` is not the spelling for a trait. It is the spelling for a
*construct family's* value, and it is what ember writes
(`-> Any RenderBackend`), because `RenderBackend` is a `construct`, not a
trait. Both existentials compile to an enum with one case per conforming
declaration and methods that dispatch on the case (`semantics/calls.klfd`,
`semantics/construct-families.klfd`).

`Copyable`, `Drop`, `Send` and `Sync` exist without a declaration; declaring one
is 3288.

### Constructs and construct families

`construct Family { ... }` declares a family, and `Family Name { ... }` — or
`construct Name() extends Family { ... }` — declares a value belonging to it.
The family has `@Required` members and members with defaults. A declaration
that answers every family member itself may leave a `@Required` member out;
reading it through the family traps there. A family no declaration joins still
has its members, so code written against it checks.

A declaration may be generic, `construct TabView<SelectionValue>(selection:
Binding<SelectionValue>) extends Widget { ... }`, as Swift's generic views
are. Its type parameters are inferred from what a call fills its inputs with,
`TabView(selection: $tab) { ... }`, or written, `TabView<Tab>(...)`. Each
instance a program names is a declaration of its own and joins the family as
its own case, so `TabView<Tab>` and `TabView<Number>` are both `Any Widget`
values and `value is TabView<Tab>` tells them apart. A family takes no type
parameters (2100).

`value is Name` on a family value says whether it holds the declaration
`Name`, and `value as Name` takes that declaration's value out; a value that
holds another declaration traps there. Both are the `match` over the family's
cases they stand for.

`construct Name { let field: T }` with no `extends` declares a struct with an
init, `Name { field: value }`, and `init(...)` inside its body writes that init.
A construct with `extends` may not declare one.

A construct member written `let name: T { ... }` is computed: reading `name`
runs the block, which ends in the value it reads as. One written
`var name: T { get { ... } set(value) { ... } }` is also assigned: `name = x`,
and `name += x`, run the `set` block with `value` bound to what is assigned.
A `set` on a `let` member is 2097. The name resolves as any member does —
bare in the construct's methods and in lambdas written inside them, through
`self.name` anywhere — so a local of the same name shadows it. One written
`let name { ... }` has the type of the value its block ends with; reading
another member written so, it sees that one's type only when that one is
declared first, and a block whose type stays unknown is 3383.

A construct member that a macro or property wrapper annotation takes up may
leave out both its type and its value, `@Wrapper var name`: the expansion
gives it what it has. One that nothing gives a type is 3383.

A name may start with `$`, `$name`, as the value a property wrapper
projects for `name` is called in Swift: a wrapper expansion declares it like
any other member. A construct literal's label `name` fills the stored member
`_name` when `name` is a computed member and the construct stores no `name`,
as Swift's memberwise initializer fills a wrapped property's storage under
the property's own name: `SettingsView(appearance: $appearance)` sets
`_appearance`.

A field annotation naming a generic struct, declared in the program or by a
framework's contract, makes that struct the field's property wrapper
(KLF-RIDL section 30): `@State var count: Number = 0` stores a
`State<Number>` as `_count`, and `count` reads its `get()` and, for a `var`,
writes through its `set(value)`. The initial value sets the instance's
`wrappedValue`, a wrapper with a `key` field gets `"<Declaration>.<field>"`
as its identity, and `@Wrapper(field: value)` sets the fields it labels.
An argument with no label sets the next field after `wrappedValue` and
`key`, in the order the wrapper declares them, as `@Environment(\.scenePhase)`
sets `Environment`'s key path (5035 when no field is left). A wrapper with a `projectedValue()`
method gives the declaration `$count`. The field is written with its type
(5034 otherwise).

A member of a struct, class, construct, enum or extension written `private`,
before or after its annotations, is used only inside the declaration writing
it and in that file's extensions of its type, as Swift's `private` is. A use
through a value anywhere else, `value.member` or `value.method()`, is 3404.

## Declarations

- `function name(parameters) -> Result { ... }`. Without `-> Result` the
  function returns `Void`. A parameter is a label and a type — `name: Type` —
  never a label and a name: `function f(list: [Int])`, called `f(list: [1])`.
  The labels are part of the function's name, as Swift's are: `pick(first:
  Int)` and `pick(second: Int)` are two functions, and a call reaches the one
  its labels name. Two declarations with the same name, labels and parameter
  types are 3003.
- A parameter is `name: Type`, `name: borrow Type`, or `name: borrow mut Type`
  (a place the function may write). The caller passes a `var` binding for
  `borrow mut`. `borrow` and `copy` bind only a value the binding leaves alone,
  so `let x: borrow [Int] = [1, 2]` is 3384; the parameter is where an array
  goes.
- `public` before a top-level function, struct, class, enum, distinct, type
  alias, construct, trait or `let` constant exports it from its package. It
  goes on no extension, import or member (2092), and alone it is 2093.
- A top-level `let` whose value is a constant is that constant wherever it is
  read: a literal, or a construction, enum case, conversion, negation or
  complement of constants, as `let read: Rights = Rights(U64(4))` is. Reads
  lower to the value in place, in its own package and in one that imports it,
  so a constant costs no load and no initializer. A `var`, a `let` worked
  out at run time, a class instance, which every reader shares as one
  object, and a `@ThreadLocal` global stay globals.
- `@ThreadLocal` before a top-level `let` or `var` gives every thread a copy
  of its own (a KIR thread-local global, section 12.7). A thread's copy is
  made from the initializer on the thread's first read, not when the program
  starts, and only the main thread's is destroyed when the program ends. A
  `@ThreadLocal var` is no shared state, so 6001 leaves it alone. The
  attribute goes on nothing else (3403).
- `namespace Name { let member: Type = value }` groups constants: the member
  is read as `Name.member`. `public namespace` exports every member at once.
- The public constant `let`s of a library go into its RIDL surface as
  `let Name.member: Type = literal`, and bindings bring them back as the same
  namespaced `let`s. An integer, an unsigned word past `Int` (as hexadecimal),
  a `Bool`, a `Number` whose mantissa fits an `Int`, a `String` and a
  distinct type over one of these all cross; a float does not, and is left
  out with a comment saying so.
- `struct Name { ... }` holds `let` and `var` fields, and methods. A field may
  declare a default with `= value`; a struct literal may then leave it out. A
  struct literal binds a field with `=` or `:` — `Point { x = 1, y = 2 }` and
  `Point { x: 1, y: 2 }` are the same literal.
- A struct member with a block in place of a value is computed, as a
  construct's is: `var area: Int { width * height }` runs the block when
  `area` is read, `let area { ... }` takes the type the block ends with, and
  `var side: Int { get { ... } set(value) { ... } }` is assigned through its
  `set` block. A computed member stores nothing, so a struct literal leaves it
  out.
- A method takes `borrow self` or `borrow mut self`; leaving the receiver out
  means `borrow self`. In a method, a bare name reads a field and a bare call
  reaches a sibling method.
- `extend Name { ... }` adds members to a type from another file or package.
- `enum Name { ... }` lists cases separated by whitespace. A case carries at
  most one payload, written `Case(Type)`, of any type in the subset.
- Generic enum and struct declarations are supported when cases and fields use
  type parameters directly, as in `Optional<Value>`, `Result<Value, Failure>`
  and `Box<Value>`. Each use is specialized to a concrete KIR type before
  lowering. A generic struct literal gets its type from the expected type, as
  in `let box: Box<Int> = Box { value = 42 }`.
- **Generic free functions are supported**, written
  `function first<Value>(values: [Value]) -> Value`. Type arguments that
  inference cannot settle are passed explicitly, `first<Int>([1, 2, 3])`;
  otherwise the call is 3316. The shipped stdlib uses two:
  `std/Foundation/app/diagnostics/Trail.kira` and `std/Foundation/app/core/NativeState.kira`.
- **Generic methods** may declare their own type parameters. An ordinary method
  call infers those parameters from its arguments and specializes the body.

### Derive markers

- `@Derive(Copy)` is an **assertion, not a generator**. It refuses any struct,
  class, enum or distinct that holds a `String`, an `Any`, an array, a class
  handle, a `Channel` end, or an owned `@FFI.Pointer`. The refusal is
  `error[3315]: bound not satisfied`, which reads as mysterious until you know
  it means "this type owns storage it cannot copy".
- `==` and `!=` compare structs, arrays and enums structurally when their leaves
  support equality. `@Derive(Equatable)` uses that implementation and retains
  `eq_Name` as a compatibility wrapper, including for optional and array fields.
  A failed compile-time macro evaluation is 5030 rather than 9001.
- `@Derive(Tagged)` numbers variants **from declaration order, counting from
  zero**, generating `code_Name` and `Name_fromCode`. A payload does not change
  a variant's code, and `Name_fromCode` answers the *first* variant for a
  number naming none. **A wire protocol that started at 16 would be silently
  renumbered.** Inserting a variant in the middle renumbers everything after
  it; that is a breaking change, not a tidy-up.
- `@Derive(CaseIterable)` generates `allCases_Name() -> [Name]`, every variant
  in declaration order, as Swift's `allCases`. A variant carrying a payload is
  refused.
- `@Derive(CustomStringConvertible)` generates
  `description_Name(value: borrow Name) -> String`, the name of the value's
  variant as it is declared, as Swift's `String(describing:)` gives a case. A
  variant carrying a payload is refused.

### Compile-time evaluation and macros

Compile-time free functions use `comptime function`. Constant scalar calls
are evaluated in the bounded KIR VM and replaced with constants before runtime
execution. Nested calls and loops run inside that evaluator. String results
are copied out of the private evaluation heap and materialized as owned runtime
buffers. Foreign calls are denied; evaluation shares a one-million-step budget
and a 16 MiB memory bound across the module's constant call sites. Runtime
arguments and unsupported aggregate results are rejected.

Inside a `comptime function` or a macro's `expand`, `Build.platform()`,
`Build.target()`, `Build.testing()` and `Build.linting()` answer what is being
built, with no arguments. `platform()` is derived from the target triple, so it
follows a cross build.

`Build.debug()` and `Build.release()` answer anywhere, as constants: a build
is a release with `--release` and a debug build without it.

Declarative macros are `macro name(param: expr, target: place) { expand {
... } }`. A parameter's category is `expr` or `place`, and anything else is
9001. Expression arguments are evaluated once, generated locals are renamed, and
nested expansion is bounded to 64 levels.

Procedural macros are `comptime macro Name { kind { ... } appliesTo { ... }
expand(...) -> Syntax { ... } }`. `kind` is `function`, `attribute`, `derive`,
`wrapper` or `collector`, and is required (5006 otherwise). A kind that
annotates declarations — the four but `function` and `collector` — requires an
`appliesTo` list (5008). An `attribute` macro whose list names `function`
annotates a top-level function: it is handed the function as a `Declaration`
of kind `.Function`, with no fields, and what it returns is added beside it. Expansion runs in a detached VM with a
500-million-step and 1 GiB bound. Derive macros receive ordinary
`Declaration` values reflecting structs, enums and distincts.

A macro edits the syntax it is handed without rereading it.
`syntax.replaceIdentifier(from, to)` respells every identifier `from` outside
strings and comments. `declaration.replaceField(name, replacement)` writes the
field `name`, annotations included, as `replacement` and keeps the bytes of
every other field where they now sit, so edits chain;
`declaration.dropField(name)` removes it. Naming a field the declaration does
not write itself is 5025. `field.annotation(name)` is the field's annotation
by that name, with the `arguments` it is written with, each its `label` and
its `value` as syntax; a wrapper passes them on to the wrapper it builds.

A **`kind { collector }` macro runs once for the whole program** and is handed
every top-level declaration, in declaration order. Each arrives as a
`Declaration` with a `name`, a `kind`, the declaration's `syntax` as source
text, its `fields`, and a **`family`: the construct family it was declared in**,
as a plain string. `declaration.family == "Pipeline"` is therefore readable for
a family the *program* declares itself, not only for ember's:

```kira
construct Pipeline {
    @Required function shader() -> String
}

Pipeline Glass { function shader() -> String { return "glass" } }

comptime macro Collect {
    kind { collector }
    expand(declarations: [Declaration]) -> Syntax {
        var rows: [Syntax] = []
        for declaration in declarations {
            if declaration.family == "Pipeline" {
                rows.append(quote { plans.append(#{declaration.name.asString()}) })
            }
        }
        if rows.count == 0 { return quote { } }
        return quote { function declaredNames() -> [String] { var plans: [String] = [] #{rows} return plans } }
    }
}
```

`family` is empty for a declaration that belongs to no family, which is why a
collector keying on a family string selects exactly the family's declarations
and nothing else. `kind` is the word the declaration was written with:
`struct`, `class`, `enum`, `construct`, `form`, `distinct`, `function` or
`other`.

Foundation's builtin derives — Equatable, Clone, Hashable, Ordered,
Serializable, Tagged, Lerp — have focused coverage. Serializable has a focused
distinct-type round trip with exact tagged wire text. An integer field writes
its spelling around its digits, `U8(7)`, and a `Number` or sized-decimal field
its spelling around its decimal text, `UN8(7)` or `Number(0.25)`; a reader
checks the tag and the conversion range-checks the value. Broader Serde shapes
remain unfinished. `quote { ... }` produces a source `Syntax` value;
identifier, syntax, integer, boolean, string and `[Syntax]` splices have
focused coverage. Strings splice as escaped literals, and syntax arrays are
separated by newlines.

### `ksl!`

`ksl!("app/Shaders/Basic.ksl")` runs the `ksl` shader driver over that file and
embeds what it wrote, as a `KslArtifact` value. **The path is relative to the
package root, not to the file writing the call**, so from `app/main.kira` the
shader at `app/Shaders/Basic.ksl` is named `app/Shaders/Basic.ksl`. A rejected
shader is 4038, after ksl's own diagnostics. Without `ksl` on the path, an
earlier build's files are read from `generated/shaders/`, and none at all is
4039. A path that is not a `.ksl` file with a stem is 9001.

### `klist!`

`klist!("Info.klist", "BundleVersion")` is the value at that key path in a
`.klist` file (`docs/klist.md`), relative to the package root like `ksl!`'s.
A dependency's file is named by its module first:
`klist!(SharedLists, "Paths.klist", "Applications")`. The key path is dict
keys and array indexes separated by dots. A string or date is a `String`, a
number a `Number`, `true`/`false` a `Bool`, data a `[U8]`, and an array of
strings a `[String]`; a dict is 4042.

A release build writes the value in as a literal and reads nothing at run
time. A debug build calls Foundation's `klistString`, `klistNumber` and their
siblings with the file's absolute path, so an edited file needs no rebuild; a
file is parsed once and read again only after a second, and the literal is the
answer when the file is gone or no longer holds the key at that type. An
unreadable file is 4040, a malformed one 4041, a missing key 4042 and a call
not written as two or three string-literal arguments 4043.

### `sourceDigest!()`

`sourceDigest!()` is a `String` of 64 hexadecimal digits: the SHA-256 of the
sources of the package calling it and of every package it imports, directly or
through another, Foundation included. An edit to any of them changes it, and
nothing else does, so a build system keys work done by the package's code on
it (`std/Build/DESIGN.md` section 5.2). It is computed only where it is
written.

`sourceDigest!("package")` is the same of the calling package's own sources
alone: an edit to a package it imports, Foundation included, or a new
toolchain, leaves it as it was. Any other argument is 9001.

## Statements

- `let` and `var` bindings, with an optional annotation and a required
  initializer.
- Tuples of two to four elements: the type `(A, B)`, the literal `(a, b)`,
  `pair.0` to read an element, `==` between two of one type, and a tuple as an
  array element or enum payload. `let (a, b) = pair` binds each element, as
  `for (a, b) in pairs` does for every element of an array; `var (a, b)`
  makes each name mutable, and `let (a, b): (A, B) = ...` annotates the tuple.
  A `(` or `[` calls or indexes only on the line its operand ends on; one that
  starts a line opens a tuple or an array, so a block can end in `(a, b)`
  after a call. A `.member` on the next line still continues a chain.
- Assignment to a `var` binding, a `var` field, or a field reached through
  `borrow mut`.
- `if`, `else if`, `else`; `while`; `break` and `continue`.
- `for name in low..high` over an integer range, **and `for name in <array>`**
  over an array or a nested one, which binds each element in turn. Both forms
  nest: `for row in nested { for v in row { ... } }`.
- `match` over an enum value. Arms name a case unqualified, may bind its
  payload (`Square(side) -> ...`) or ignore it, and take one statement or a
  block. A `match` covers every case. An integer, a `Bool` or a `String`
  subject takes arms of literals and ranges of its own kind, and needs `else`.
  A `Number` subject takes those and, besides, a decimal literal and a range
  of decimals: `0.5`, `0.1..0.2`, `20.25..30`. Each is read as the number it
  spells, so `0.50` is fifty hundredths and `-0.50` is fifty hundredths of a
  negative, and two arms of one number are one arm written twice (3127)
  however differently they were written. The subject is ordered by value and
  not by its two words.
- `attempt { let x = try f() ... } handle { Case { ... } }` unwraps a `Result`
  whose `Error` payload is a failure enum, and a `handle` arm takes that case.
  `try` outside an `attempt` initializer is 3137, and a `try` over an `Error`
  payload that is not a failure enum is 3138.
- `i++` and `i--` step a binding by one, and `+=`, `-=`, `*=`, `/=` and `%=`
  read as the same statement with `i = i + x`. They are not integers only:
  `total += 1` on a `Number` and `word += "b"` on a `String` are the two that
  come up, and both are the ordinary operator with the old value as an operand.
- `return`, with a value unless the function returns `Void`.
- `log(...)` and `log <level>(...)` record an event on Foundation's trail,
  at `fault`, `warn`, `info` (the default), `debug` or `trace` (2094). A
  leading string literal is the message, which `fault` and `warn` require
  (2095); each other argument is a field named by its label or its source
  text, and a literal field needs a label (2096). A field is any value,
  shown as `traceText` shows it, and is evaluated only when the event
  records. An event prints as a compiler diagnostic does: the site, the line
  it is written on with carets under it, then `= name: value` for each
  field. Events down to `debug` are kept in a ring of 256 and written out
  before a fault, a trap or a failure. `KIRA_LOG` (`info`,
  `Shop.net=trace,warn`, `off`) sets what prints, per trail; unset, a program
  prints every event from `info` up, its libraries' as well as its own.
- `log(category: Enum.Case, ...)` writes to a category. `Enum` is an enum that
  conforms to Foundation's `LogCategory` (`function threshold(borrow self) ->
  TrailThreshold` gives each case its declared default). The category's path
  is the module's name, the enum and the case: `Network.Tls.Handshake`. Written
  any other way, the `category:` value is 2105. A log without the argument is in
  the module's implicit category. At runtime `Log.enable(path, level)`,
  `Log.disable(path)`, `Log.set(path, threshold)`, `Log.reset(path)` and
  `Log.categories()` change and list them; `KIRA_LOG` rules have the same paths,
  and a family `Network.Tls.*` names every path under `Network.Tls`. Precedence,
  lowest first: the declared default, `KIRA_LOG`, the calls. The design and what
  is not yet built are in `logging.md`.
- Failures leave the trail too, with nothing written for them. `try X
  otherwise Y` is `X`'s value, or `Y` when it fails, recording that it fell
  back; `Y` may be `return ...`. `X` is a result, whose `Ok` value it gives
  and whose `Error` it falls back from, or an optional value, whose `Some`
  value it gives and whose `None` it falls back from; `None` is an absence,
  not a failure, and records nothing. Anything else is 3138. `absorb failure` records a
  failure let go where a `match` takes one apart. A `handle` arm records the failure it
  handles, and `return .Error(...)` records where a failure was made, or,
  while another is being handled, that it converted that one. An event that
  takes a failure shows, under it, the way the failure came: each `:::`
  site that made, handled or converted it, up to eight.
- A `match` on a result binds the failure its `Error` arm takes: an `Error`
  arm with no binding or `_`, or an `else` arm standing for `Error`, is
  refused (3394). The failure is used, passed on, or let go with `absorb`.
- `traceText(value)` is any value as a trail shows it: a struct's fields to
  three levels (`Point { x: 1, y: 2.5 }`), an array's first three elements
  and how many more, an enum's case and payload, a string quoted, escaped and
  cut at 80 bytes, and only the type's name for what has no readable
  contents. A type conforming to Foundation's `Traced` chooses what it shows:
  `function traced(borrow self) -> Trace` returns `Trace(...)`, which takes
  what `log(...)` takes, and reads `Mesh(name: "hull", vertices: 1204)`.

## Expressions

- Integer literals (decimal and `0x` hexadecimal), float literals, `true` and
  `false`.
- Names, field reads, calls, method calls, generic calls, and struct literals
  (`Point { x = 1, y = 2 }`).
- Enum cases written `.Case` or `.Case(payload)`. The enum comes from the
  position: an annotation, a parameter, a field or the other side of `==`.
- Arithmetic `+ - * / %`, bitwise `& | ^ ~`, shifts `<< >>`, comparisons,
  `&&`, `||`, `!`, unary `-`, and `condition ? a : b`.
- `wrappingAdd`, `wrappingSub` and `wrappingMul`, which wrap at the operands'
  width.
- Lambdas, written `{ x in ... }`, taking their parameter types from a
  function-type annotation: `let g: (Int) -> Int = { x in return x + 1 }`. A
  parameter may be written with its type, `{ x: Int in ... }`; passed to a
  generic function or method, that type binds the type parameter the callable
  parameter names there, as `{ playground: Playground in ... }` passed for
  `(Value) -> Any Widget` binds `Value`. A lambda captures immutable bindings by value and a `var` by shared cell. A
  lambda capturing a `borrow mut` parameter is 9001.
- Key paths, written `\Root.member.member`, or `\.member` where the type
  expected is a function from the root. A key path is the function borrowing
  a `Root` and reading the member path from it, of Foundation's type
  `KeyPath<Root, Value>`, `(borrow Root) -> Value`: `let depth =
  \Values.inner.depth` reads with `depth(values)`. A `\.member` with no
  function type expected is 3050, and a member the type does not have is 3091.
  A generic parameter of a function type binds from the argument's type, as
  `Value` does in `read<Value>(path: KeyPath<Values, Value>)`.
- `print(value)` writes any non-`Void` value. Scalars keep their ordinary output;
  aggregates use `traceText`. `log` renders `Number` fields as decimal text.
- String interpolation, `"\(value)"`, renders expressions inside a literal.
- `T?` is shorthand for `Optional<T>`, including array and callable types. A
  `T` where a `T?` is wanted is that optional holding it, as Swift promotes
  one: `width(7)` for `width: Int?`, `let name: String? = "kira"`, `return 3`
  from a function returning `Int?`. An optional is never promoted into another,
  and `.None` is still how none is written.
- `Result<Void, Failure>` uses `.Ok` without a payload.
- `for (index, value) in values.enumerated()` binds both the position and value.
- `enum Key: U32 { F12 = 69 }` declares stable raw values. `code(key)` and
  `fromCode<Key>(raw)` use them rather than declaration-order indexes. A raw
  value no case names traps.
- `@Open enum Key: U32 { Escape = 41 F12 = 69 }` keeps a raw value no case
  names: `fromCode<Key>(7)` holds 7, `code` gives it back, and a `match` on it
  needs `else`. It traces as `Key(7)`, a named case as `Key.F12`.
- Distinct integer flags support bitwise operators and `.has(flags)`.

### Channels

`Channel<T>()` makes a channel; `tx.send(value)` sends, `tx.receiver` is the
other end, `tx.close()` closes it, and `try rx.receive()` takes one message.
A drained closed channel returns the `Closed` case, which an `attempt`/`handle`
catches. A receive on a drained open channel drives deferred tasks, and traps
if none can run.

### Native state

`nativeState(value)` boxes a value for a host to hand back through an opaque
word; the handle is `NativeState<Boxed>` and gives up its reference at the end
of its scope. `nativeUserData(handle)` and `nativeUserDataBorrow(handle)` turn
it into a `RawPtr` token, `nativeUserDataRetain(token)` and
`nativeUserDataRelease(token)` manage one more owner, and
`nativeStateValue(token)` reads the boxed value back. `nativeStateFree` is
deprecated (3360, a warning): it releases one reference, not the state.

### The raw heap builtins

These are **bare builtins**. They need no `@FFI.Extern`, no `NativeLibrary` in
`package.kira`, and no `linkMode: LinkMode.Runtime` row, because they are
dispatched before any name lookup (`semantics/calls.klfd`). A user declaration
of one of these names does not shadow it.

| Call | Signature |
| --- | --- |
| `heapAllocateRaw(byteCount, alignment)` | `RawPtr` |
| `heapFreeRaw(pointer)` | `Void` |
| `heapReadInt(pointer)` | `Int` |
| `heapReadByte(pointer)` | `U8` |
| `heapWriteInt(pointer, value)` | `Void` |
| `heapWriteByte(pointer, value)` | `Void` |
| `heapCopyBytes(destination, source, count)` | `Void` |
| `heapMoveBytes(destination, source, count)` | `Void` |
| `heapFillBytes(destination, byte, count)` | `Void` |
| `heapOffset(pointer, byteOffset)` | `RawPtr` |
| `heapLoad<T>(pointer)`, `heapLoad<T>(pointer, byteOffset)` | `T` |
| `heapStore<T>(pointer, value)`, `heapStore<T>(pointer, byteOffset, value)` | `Void` |
| `sizeOf<T>()`, `alignOf<T>()` | `Int` |

`heapOffset` is the pointer arithmetic the section below says the first two
do not provide. `heapCopyBytes` is for ranges that do not overlap;
`heapMoveBytes` copies between ranges that may.

**Typed memory.** `heapLoad` and `heapStore` read and write a value as C lays
it out, at any alignment, and `sizeOf`/`alignOf` give that layout. The type is
the one written in `<T>`, or else the type the load is expected as, or the
stored value's own; a load with neither is 3396. It must have a C memory
shape (3397): an integer, float, `Bool` (one byte), `RawPtr`, an enum without
payloads (a C `int` of its case index), an `@FFI.Struct`, `@FFI.Union`,
`@FFI.Array`, callback or pointer type, or a `distinct` over one. A program's
own generic function named `heapLoad`, `heapStore`, `sizeOf` or `alignOf`
is called in place of the builtin.

**Values with a drop are not copied (3398).** A struct whose `drop` runs,
itself or through a field, is dropped once, by its last holder, and so is an
enum one of whose payloads is such a value, `Result<ByteBlock, String>` for
one. Reading one
held in a binding, member or element as a value would copy it and run the
drop twice, so it is refused: hand it over with `move` (`return move block`)
or lend it with `borrow`. Writing a fresh value over one is not a copy.

**Atomics.** Each of these is one atomic instruction on the value at a raw
pointer, ordered by a `MemoryOrder` case (Foundation) written at the call:

| Builtin | Answers |
|---|---|
| `atomicLoad<T>(pointer, order)` | `T` |
| `atomicStore<T>(pointer, value, order)` | `Void` |
| `atomicExchange`, `atomicAdd`, `atomicSubtract`, `atomicAnd`, `atomicOr`, `atomicXor`, `atomicMax`, `atomicMin` `<T>(pointer, value, order)` | the `T` it replaced |
| `atomicCompareExchange<T>(pointer, expected, replacement, success, failure)` | the `T` it read |
| `atomicCompareExchangeWeak<T>(pointer, expected, replacement, success, failure)` | `Bool`, whether it exchanged |
| `atomicFence(order)` | `Void` |

`T` is an integer, a sized number such as `N32`, or, for loads, stores and
exchanges, a `RawPtr` (otherwise 3407). `atomicMax` and `atomicMin` compare as
`T` is signed. `atomicCompareExchange` exchanged exactly when it read
`expected`; the weak form may fail spuriously, so it belongs in a loop. The
ordering is a case written at the call and one the operation can have (3408):
a load neither releases nor `AcquireRelease`s, a store does not acquire, a
fence is not `Relaxed`, and a compare-exchange's failure ordering is a load's
no stronger than its success ordering. A program's own function of one of
these names is called in place of the builtin.

**Awaits** (`semantics/async.klfd`, `semantics/await-hoist.klfd`). In an
`async function`, `future.await` may be written anywhere a statement
evaluates once before it runs: a binding's or assignment's value, a returned
or evaluated expression, an operand, an argument, an `if` condition, a
`match` subject, a `for` loop's bounds. Each await written inside such an
expression runs before the statement, in a binding of its own, after
whatever the expression evaluates before it. An await on the right of `&&`
or `||`, in a conditional's branch, in an arm of a `match` value, in a
`while` condition or in a lambda runs only some of the time and is 9001.

**Threads** (Foundation `Thread.kira`, KLF section 18.9).
`spawnThread({ in ... })` runs a lambda on a thread of its own and answers a
`Thread`; `join()` waits for it, and dropping the `Thread` joins it, so a body
never outlives what it captured. Threads share the heap: a value made on one
is read, retained and released on any other. What a body captures is shared
with its caller, so state both change is an atomic or is guarded by one.
`currentThread()` answers the calling thread's `ThreadId`, whose `unpark()`
wakes it from `parkThread()` (or makes its next park return at once);
`parkThreadFor(nanoseconds)` returns by then at the latest, a park may return
spuriously, and a caller rechecks what it waits for. `yieldThread()` offers
the processor away, and `threadParallelism()` is how many threads run at
once. On the VM an instance has one thread: `spawnThread` runs the body to
its end before it returns.

### The Heap library

`std/Heap` is built on these builtins.
array-data functions the compiler calls, it holds:

- `MemoryLayout` (`Layout.kira`): a checked size and power-of-two alignment
  from `memoryLayout(size, alignment)`, `layoutOf<T>()` or
  `arrayLayout<T>(count)`, with `stride`, `padded`, `fieldOffset`, `extended`
  and `repeated`; `alignUp`, `alignDown` and `isPowerOfTwo`.
- Raw memory (`Memory.kira`): `allocate`, `allocateZeroed`, `reallocate` and
  `deallocate`; `copyBytes` (overlap traps), `moveBytes`, `fillBytes`,
  `zeroBytes`, `compareBytes` and `bytesEqual`; `nullPointer`, `isNull`,
  `pointerAddress`, `pointerAt`, `pointerDistance`, `isAligned` and
  `alignPointer`.
- `MemoryView` (`View.kira`): a bounds-checked window it does not own, with
  `readU8` to `readF64`, `readBool`, `readPointer`, their `write` twins,
  `slice`, `fill`, `zero`, `copyFrom`, `equals` and `compare`, and the generic
  `viewLoad<T>`, `viewStore<T>`, `viewElement<T>` and `setViewElement<T>`.
- `ByteBlock` (`Block.kira`): owned bytes freed by its drop, from
  `zeroedBlock`, `uninitializedBlock`, `blockOf<T>`, `blockCopying` or
  `adoptBlock`, with `view`, `resize`, `duplicate` and `release`, and
  `blockLoad<T>`/`blockStore<T>`.
- `Boxed<Value>` (`Boxed.kira`): one C-shaped value in a block of its own at a
  fixed address, from `boxed<T>`, read and written with `boxedValue<T>` and
  `setBoxedValue<T>`.
- `Arena` (`Arena.kira`): bump allocation through linked chunks from
  `makeArena(chunkSize)`, with `allocate`, `allocateZeroed`, `zeroedView`,
  `reset` and `blockCount`, and `arenaStore<T>` and `arenaArray<T>`; it frees
  everything at `reset` or when let go.

Every count, offset and range is checked and traps outside its bounds.
Foundation's `HeapBytes.kira` bridges to arrays, which `Heap` lies beneath:
`blockFromBytes([U8])` and `viewBytes(view)`.

**`heapAllocateRaw` does not zero.** A `kira_dynamic_alloc` reached through
the `kira_runtime` `LinkMode.Runtime` library does. The two are not the same
call, and the difference matters: `std/Heap` writes a header into the bytes it
allocates and never relies on them starting at zero, while code that assumes a
fresh allocation is clean and used `kira_dynamic_alloc` does not get that.

## Foreign functions

The `.klffi` forms of the framework's section 26 cross into C:

- `@FFI.Extern { library, symbol, abi: c }` on a function with no body, with
  `retains: <parameter>` for each argument C keeps; `@FFI.Variadic` after it
  makes the function C variadic, so a call passes extra arguments, promoted
  as C promotes them. The values in a callable form's block are **bare words**,
  not strings: `@FFI.Syscall { name: write }`, not `{ name: "write" }`.
- `@FFI.Address { library, symbol }` is the address of a C data symbol, and
  `@FFI.Syscall { name }` a Linux system call by its `man 2` name, with at
  most six arguments; a target other than Linux or Android refuses
  it when the program is built. A program reaches the operating system
  through services, never through system calls of its own (framework
  D-382): only a package whose manifest writes `let systemCalls: Bool = true`,
  the system itself, declares one (3409 anywhere else).
- `@FFI.Struct { layout: c }` and `@FFI.Union { layout: c }` lay a struct out
  as C does, including bit-fields written `let flags: U32 @Bits(3)`.
- `@FFI.Pointer { target, ownership }` names a pointer that is `borrowed`,
  `unmanaged` or `owned`; an owned one names its `free:` function, is freed
  once, and is moved rather than copied (3378).
- `@FFI.Array { element, count }` is a fixed C array, `@FFI.Alias` a C scalar
  whose width depends on the target, and `@FFI.Callback { abi: c, params,
  result }` a C function pointer. A function or a lambda that captures
  nothing converts to it; a lambda that captures needs `context: <parameter>`,
  the `void *` C hands back to the callback (3380). A value of a callback
  type is also called as a function, `pointer(a, b)`, which calls C through
  it with the platform convention (KLF section 26.4); a parameter or result C
  passes as a struct by value cannot cross a pointer (3182).
- A `NativeLibrary` in `package.kira` names the library a declaration's
  `library:` refers to: its `binary`, its `header`, its `.klffi` declarations
  (`klffi:`, compiled as one more source of the package) and its
  `linkerFlags`. Kira's longer spelling — `linkMode`, `headers`, `sources`,
  `autobind`, `nativeTargets` — is accepted as well.
- `autobind: Autobind { module, headers, mode }` makes the declarations from
  the library's C headers when the package is loaded, as `klf ffi gen` does:
  its functions, structs, enums and constants. `AutobindMode.Selected` keeps
  only the functions `functions:` lists. A header is found under the package
  or one of the library's `includeDirs`, and one that is in neither is 4036.
  A package that keeps `app/bindings/<module>.kira`, as Kira's own autobind
  writes it, has its bindings already, and its headers are not read.

### `@Service` and the `kira_runtime` library

`@Service("klfsvc_io_write")` on a function with no body declares a symbol the
platform's KLF runtime implements, so Foundation reaches files, clocks and
maths through the kernel rather than through any platform library. The rules
are strict and are checked: no body (3369), a free and non-generic function,
parameters that are owned `RawPtr`, `Int` or `U64`, and a result that is one
of those or `Void` (3368). Anything else in the signature is 3368.

**The compiler does not check that the symbol exists.** Any name is accepted,
including one no runtime exports; the failure is a link error, not a
diagnostic. `klf-native-rt` exports several hundred `klfsvc_*` symbols — every
`klfsvc_kir_*`, `klfsvc_source_*`, `klfsvc_shader_*` and `klfsvc_test_*`
service, as well as the program-facing ones — so a symbol is not something to
guess at. The program-facing set Foundation uses is `klfsvc_io_write`,
`klfsvc_io_write_error`, `klfsvc_fs_read`, `klfsvc_fs_write`, `klfsvc_fs_list`,
`klfsvc_fs_file_exists`, `klfsvc_fs_path_exists`, `klfsvc_fs_is_directory`,
`klfsvc_fs_file_size`, `klfsvc_fs_make_directory`, `klfsvc_fs_remove_path`,
`klfsvc_fs_rename`, `klfsvc_process_environment`, `klfsvc_process_argument`,
`klfsvc_process_argument_count`, `klfsvc_process_invoked_as`,
`klfsvc_process_exit`, `klfsvc_time_sleep`, `klfsvc_time_wall`,
`klfsvc_time_monotonic`, `klfsvc_text_float`, `klfsvc_math_unary`,
`klfsvc_math_binary` and `klfsvc_number`. `@Service` is Foundation's own mechanism and needs no
import to use.

**It is not a way to reach a Linux system call.** A syscall wrapper is
`@FFI.Syscall { name: write }` and nothing else — that is what
`packages/linux` declares, and there is no `@Service` spelling of it. Writing
both annotations on one function compiles but is not the mechanism: the
`@FFI.Syscall` form is what lowers to the instruction.

### `LinkMode.Runtime` lowers in place

A `@FFI.Extern` against a `kira_runtime` library declared
`linkMode: LinkMode.Runtime` is **not linked as a symbol**. A naming rule
matches it and it lowers in place to the heap operation it stands for
(`lowering/kira-runtime.klfd`):

- `kira_dynamic_alloc` → a zeroed allocation (`allocateRaw`, then zeroed)
- `kira_dynamic_free` → the raw free; freeing a null pointer frees nothing
- `kira_dynamic_null_ptr`, `kira_dynamic_ptr_is_null` → constant 0 and a
  comparison against it
- `kira_dynamic_read_<T>_at(pointer, offset)` → a load at that offset, of the
  width the declaration gives
- `kira_dynamic_write_<T>_at(pointer, offset, value)` → a store at that offset

Any *other* symbol bound through the same library — libc's `strcmp`, which
every process has loaded — is called as ordinary C. So the zeroing difference
above is between two lowering paths, not between two runtimes.

## Runtime checks

Every check traps with a KLF runtime code, which the program prints as
`TRAP <code>`:

- `+ - *` trap when the result leaves the written width (`KLF-RT-0002`).
- A conversion traps when the destination cannot hold the value.
- Division and remainder trap on a zero divisor (`KLF-RT-0010`), and signed
  division of the minimum value by -1 traps (`KLF-RT-0002`).
- A shift traps when its count is outside `0..width`.

## Documentation comments

`///` documents the declaration written right after it, and `//!` documents the
file. The parser attaches them to top-level declarations, struct fields and
methods, and enum cases and methods; a doc comment that documents nothing is
error 2101, and a `//!` after the file's first token is 2102. `kira doc`
renders the package's public API from them, and `kira doc --check` reports
public declarations without one (2103). The format is in
docs/documentation.md.

## Outside the subset

9001 marks a construct outside the supported subset. Missing Foundation for
text or rendering is 3400; compile-time macro evaluation failure is 5030.

### Not compiled

- a dotted `import` path (`import A.B`);
- an annotation with arguments other than `@Derive(...)`, `@Service("...")`
  and the `@FFI.*` forms, and any annotation written `@Name { ... }`;
- a declarative macro parameter whose category is not `expr` or `place`, a
  `place` argument that is not a name, a macro body that does not parse to
  its end, and expansion nested deeper than 64 levels;
- a lambda that captures a `borrow mut` parameter;
- a `ksl!` argument that is not a `.ksl` path with a stem, and a
  `.resources` file that is not SPIR-V words.

### Deliberately excluded

- a string literal, a `quote` when `Syntax` is not a struct holding one
  `String`, or a splice of a value of another type than identifier, syntax,
  integer, boolean, string and `[Syntax]`, in a program with **no `String`
  type**. This is not a rule about the construct; it is what happens when
  Foundation has not been loaded. `import Foundation` fixes it, or a
  `dependencies` row naming it — `import Foundation` resolves from the
  bundled std even with no row.
- a task body that is not one expression, and a main-thread operation kira
  does not know.

### Missing imports and unrecognised names

Missing declarations normally report lookup diagnostics. Missing Foundation
for literals or tracing reports 3400:

- `traceText(value)` in a program with no `String` type — the same missing
  Foundation as above.
- a content call with no callee.

The generated [diagnostic reference](diagnostics.md) is the source for current
codes. [Idiomatic Kira](idiomatic-kira.md) describes the intended style.
