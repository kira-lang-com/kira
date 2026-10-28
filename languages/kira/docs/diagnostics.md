# Diagnostic codes

Generated from `definitions/language.klfd` by `tools/generate-diagnostics.py`.
Do not edit this table by hand.

The compiler reports a numeric code and a source range. The thousands
band identifies the phase: 1xxx lexer, 2xxx parser, 3xxx semantics,
4xxx packages, and 5xxx macros. Warnings do not fail a compilation.

| Code | Severity | Message | Explanation |
| --- | --- | --- | --- |
| 1001 | error | unexpected character | this byte is not a valid Kira token |
| 1002 | error | unterminated string literal | the string is not closed before the end of the line |
| 1003 | error | unknown string escape | the escapes are \\n \\t \\r \\e \\0 \\" \\\\ and a line break, which continues the string |
| 1004 | error | unterminated block comment | this `/*` is never closed, and block comments nest |
| 1005 | error | `;` is not Kira syntax | a statement ends where its grammar ends |
| 2001 | error | unexpected token | the parser expected a different token here |
| 2002 | error | expected a declaration | a file holds functions, structs and enums |
| 2003 | error | expected an annotation name | an annotation is `@` and a name |
| 2004 | error | expected a function name | `function` is followed by the function's name |
| 2005 | error | expected a parameter name | a parameter is written `name: Type` |
| 2006 | error | expected a type name | a type is written by its name |
| 2007 | error | expected a struct name | `struct` is followed by the struct's name |
| 2008 | error | expected a class name | class is followed by its name |
| 2009 | error | expected a struct member | a struct member starts with `let`, `var` or `function` |
| 2010 | error | expected a name | a binding or member needs a name |
| 2011 | error | a binding needs an `=` initializer | definite initialization begins at the declaration |
| 2012 | error | expected a loop variable | `for` is followed by the name each iteration binds |
| 2014 | error | expected an enum variant name | a `match` arm starts with the variant it handles |
| 2015 | error | expected a payload binding | the parentheses of an arm name the variant's payload |
| 2016 | error | expected a module name after `import` | `import` is followed by the name of a library the package depends on |
| 2020 | error | expected an expression | this token cannot start an expression |
| 2021 | error | integer literal is too large | the literal is past 2^64, more than a `Number` holds |
| 2022 | error | expected a field name | `.` is followed by a field or method name |
| 2023 | error | expected a field name in a struct literal | a struct literal lists `field = value` pairs |
| 2024 | error | expected `=` after a field name | a struct literal binds a field with `=` or `:` |
| 2030 | error | expected an enum name | `enum` is followed by the enum's name |
| 2031 | error | expected an enum variant name | a variant is written by its name |
| 2032 | error | expected a type alias name | a type declaration needs a name |
| 2047 | error | generic member | a member cannot declare its own type parameters; write the concrete types out |
| 2048 | error | expected an `@FFI` block | an `@FFI.*` annotation is followed by its `{ key: value, ... }` block |
| 2049 | error | expected an `@FFI` field name | each field of an `@FFI.*` block starts with its name |
| 2050 | error | expected `:` after an `@FFI` field name | an `@FFI.*` field is written `name: value` |
| 2051 | error | expected an `@FFI` field value | a field's value is a word, a type, an element count or a `[Type, ...]` list, by its name |
| 2052 | error | expected `,` between `@FFI` fields | the fields of an `@FFI.*` block are separated by commas |
| 2053 | error | unknown qualified annotation | the qualified annotations are the `@FFI.*` family: Extern, Address, Syscall, Variadic, Struct, Union, Pointer, Array, Callback and Alias |
| 2057 | error | expected a construct name | construct is followed by its name |
| 2065 | error | expected a builder body | `For(name in source)` is followed by the `{ ... }` of children it produces |
| 2066 | error | computed member without a type | a computed `let` member states its result type, and a stored one without a type has an initializer to take it from |
| 2075 | error | a bare `self` receiver | write `borrow self` or `borrow mut self`; Kira has no consuming receiver |
| 2077 | error | construct parameters without a family | a construct with a parameter list is a declaration, and extends the family backing it |
| 2078 | error | construct declaration names two families | a construct declaration is backed by exactly one family |
| 2084 | error | expected a distinct type name | distinct is followed by its name |
| 2085 | error | expected a distinct representation | a distinct declaration needs = Representation |
| 2092 | error | `public` applies only to a top-level declaration | `public` exports a function, type, constant or trait; extensions, imports and members take no visibility |
| 2093 | error | `public` must be followed by a declaration | write the declaration `public` exports right after it |
| 2094 | error | unknown log level | a `log` level is `fault`, `warn`, `info`, `debug` or `trace` |
| 2095 | error | log without a message | a `fault` or `warn` event is read by a person, so it starts with a string literal saying what happened |
| 2096 | error | unnamed log field | a field is named by its label or its source text, and a literal says nothing; label it, as in `log("sent", bytes: 4)` |
| 2097 | error | setter on a `let` member | a computed member with a `set` accessor is assigned to, so it is declared with `var` |
| 2098 | error | `@Native` is not valid on a Kira function | remove `@Native`; foreign declarations use `@FFI.Extern` or `@FFI.Syscall` |
| 2099 | error | declaration shadows a builtin | rename the function, method or binding; `code`, `compare`, `hash`, `print` and `traceText` are builtin functions |
| 2100 | error | generic family | a family takes no type parameters; a declaration backed by it may, as `construct TabView<Selection>(selection: Binding<Selection>) extends Widget` |
| 2101 | error | doc comment without a declaration | a `///` doc comment documents the declaration written right after it; move it onto one, or change it to `//` when it explains code rather than the API (docs/documentation.md) |
| 2102 | error | inner doc comment after the first token | a `//!` doc comment documents the file and must come before the file's first token; write it at the top of the file |
| 2103 | error | public declaration without documentation | `kira doc --check` needs a `///` doc comment on every public declaration and on each field, method and case of a public type (docs/documentation.md) |
| 2104 | error | unknown documentation format | `kira doc --format` takes `markdown` (the default) or `json` (docs/documentation.md) |
| 2105 | error | log category not written Enum.Case | `category:` names the case a log is written to, as `Enum.Case` (for example `log(category: Tls.Handshake, "sent")`); a log has one category |
| 2106 | error | unresolved intra-doc link | a `[`name`]` link in a doc comment names no item of the package, so `kira doc` cannot link it (docs/documentation.md) |
| 2107 | error | doc example does not compile | a fenced code block under `# Examples` is checked by `kira doc --check`, which compiles it as Kira in a package that imports the documented one (docs/documentation.md) |
| 2108 | error | compile_fail doc example compiles | an example marked `compile_fail` must fail to compile, and this one compiled |
| 3003 | error | duplicate function | a function with this name, these labels and these parameter types is already defined |
| 3004 | error | duplicate type | a type with this name is already defined |
| 3005 | error | duplicate field | the struct already has a field with this name |
| 3007 | error | duplicate variant | the enum already has a variant with this name |
| 3010 | error | more than one `@Main` | a program declares one entrypoint |
| 3011 | error | no `@Main` function | the program has no `@Main` function to run |
| 3012 | error | an entrypoint takes no parameters | `@Main` marks a function with no parameters |
| 3020 | error | binding type mismatch | the value does not have the type the binding is annotated with |
| 3021 | error | mutation through an immutable binding | declare the binding with `var` to mutate it or pass it as `borrow mut` |
| 3022 | error | assignment type mismatch | the value does not have the type of the place it is assigned to |
| 3023 | error | assignment to an undefined name | no binding with this name is in scope |
| 3024 | error | assignment to an immutable field | declare the field with `var` to assign to it |
| 3025 | error | assignment to an immutable binding | declare the binding with `var` to assign to it |
| 3027 | error | not in scope in this file | this name belongs to a library this file does not import; another file's `import` does not carry over |
| 3030 | error | missing return value | this function must return a value of its result type |
| 3031 | error | `Void` function returns a value | a function without a result type returns nothing |
| 3032 | error | return type mismatch | the value does not have the function's result type |
| 3033 | error | missing return | this function may finish without returning a value |
| 3040 | error | condition is not `Bool` | a condition must be `Bool`; Kira has no truthiness |
| 3042 | error | `break` or `continue` outside a loop | there is no loop here to leave |
| 3043 | error | range bound is not an integer | a `for` range bound must be an integer |
| 3050 | error | unknown type | no type with this name is declared |
| 3051 | error | class inheritance cycle | this class resolves back to itself through its parents |
| 3052 | error | struct contains itself | a struct cannot hold itself by value; its fields form a cycle with no finite size |
| 3059 | error | override changes the field type | an `override let` that restates a type must restate the inherited field's type |
| 3060 | error | undefined name | no binding with this name is in scope |
| 3061 | error | call to an undefined function | no function with this name is declared |
| 3062 | error | wrong number of arguments | the call passes a different number of arguments than the function takes |
| 3070 | error | operator does not apply | this operator cannot apply to a value of this type |
| 3071 | error | operand types disagree | both operands must have the same type |
| 3080 | error | builtin takes a different number of arguments | `print`, `abort`, `code`, `fromCode` and `hash` take one value, and `compare` takes two |
| 3081 | error | builtin argument has the wrong type | `print` renders a `String`, an integer, a `Float` or a `Bool`; `code` takes an enum value; `fromCode<E>` takes an `Int` and an enum `E` whose variants carry no payload; `compare` takes two values of one type and answers Foundation's `Ordering` |
| 3090 | error | no fields | a value of this type has no fields |
| 3091 | error | unknown field | the struct has no field with this name |
| 3092 | error | unknown struct | a struct literal names a struct that is not declared |
| 3093 | error | field initialized twice | this field is already given a value in the literal |
| 3094 | error | field type mismatch | the value does not have the field's type |
| 3095 | error | missing field | a struct literal leaves out a field that declares no default |
| 3104 | error | empty array without a type | `[]` holds nothing to infer an element type from; annotate what it holds, as in `let xs: [Int] = []` |
| 3105 | error | array elements disagree | every element of an array literal has the first element's type, and numbers do not widen |
| 3106 | error | value is not iterable | a for loop takes an array or an integer range |
| 3107 | error | use after move | this binding was moved and is no longer available |
| 3108 | error | passing a named value to an owned parameter transfers ownership | write `move name` to give the value away, or declare the parameter `borrow` to lend it |
| 3111 | error | cannot move a borrowed value | the borrowed parameter belongs to its caller |
| 3113 | error | passing a named value to a `copy` parameter copies a non-trivial value | a string, struct, array, enum or `Any` owns what it holds; pass a temporary, or borrow it |
| 3117 | error | cannot move a captured variable | this variable is shared through a closure capture cell |
| 3119 | error | variant without an enum | a leading-dot variant needs a position that expects an enum |
| 3120 | error | unknown variant | the enum has no variant with this name |
| 3121 | error | variant takes no payload | this variant carries nothing |
| 3122 | error | variant takes one payload | this variant carries exactly one payload value |
| 3123 | error | payload type mismatch | the value does not have the variant's payload type |
| 3124 | error | missing payload | this variant requires a payload value |
| 3125 | error | `match` subject is not an enum, an integer, a Bool, a `Number` or a `String` | a `match` dispatches on an enum's variant, or on the value of an integer, a `Number`, a `Bool` or a `String` |
| 3126 | error | unknown variant in `match` | the subject's enum has no variant with this name |
| 3127 | error | variant matched twice | an earlier arm already matches this variant |
| 3128 | error | nothing to bind | this variant carries no payload to bind |
| 3129 | error | `match` is not exhaustive | every variant of the subject's enum, or both Bool values, needs an arm, unless an `else` arm takes the rest; an integer subject needs `else` |
| 3130 | error | duplicate alias name | this alias claims a name another declaration already has |
| 3131 | error | `? :` condition is not `Bool` | the condition of `? :` must be `Bool` |
| 3132 | error | `? :` branches disagree | both branches of `? :` must have one type |
| 3137 | error | try has no failure destination | try must initialize a let directly inside an attempt body |
| 3138 | error | try needs a Result | try unwraps an Ok/Error enum whose Error payload is a failure enum, or the failure the function itself returns; try X otherwise Y also takes an optional value |
| 3139 | error | handle is not exhaustive | handle must cover every case of the failure enum |
| 3140 | error | unknown failure variant | this name is not a case of the failure enum |
| 3141 | error | incompatible try failures | every try in this attempt must use the same failure enum |
| 3142 | error | failure handled twice | an earlier handle arm already covers this failure |
| 3143 | error | attempt has no try | an attempt body must contain a try initializer |
| 3157 | error | type alias cycle | this alias resolves back to itself |
| 3174 | error | wrong number of type arguments | a generic declaration was given a different number of type arguments than it declares parameters |
| 3175 | error | instantiation without end | a generic declaration instantiates ever larger versions of itself |
| 3176 | error | `CString` outside a foreign signature | `CString` is the C seam's string: it is written as an `@FFI` parameter, result or C-layout field |
| 3177 | error | `@FFI` function with an execution or export annotation | a foreign function is called, not run as an entry, on the main thread, on a chosen engine or exported |
| 3178 | error | unknown `@FFI` field | `@FFI.Extern` takes `library`, `symbol`, `abi` and `retains`; `@FFI.Syscall` takes `name` |
| 3179 | error | `@FFI` field set twice | each field of an `@FFI` block but `retains` is written once |
| 3180 | error | missing `@FFI` field | `@FFI.Extern` names its `library`, `symbol` and `abi`; `@FFI.Address` its `library` and `symbol` |
| 3181 | error | unsupported foreign ABI | `@FFI.Extern` supports only the C ABI, `abi: c` |
| 3182 | error | type cannot cross the C seam | a foreign signature carries scalars, `CString`, `RawPtr`, payload-less enums, distinct scalars, arrays of scalars as parameters, and `@FFI` types |
| 3183 | error | argument type mismatch | the argument does not have the parameter's type |
| 3184 | error | foreign name already a function | an `@FFI` function shares the call namespace with every other function |
| 3185 | error | foreign function declared twice | an `@FFI` function name is declared once |
| 3186 | error | no C zero value | a C-layout literal leaves out a field whose type has no zero: give it a value in the literal; an `@FFI.Address` function, which answers an address, takes no parameters |
| 3187 | error | `@FFI` form in the wrong position | Extern, Address, Syscall and Variadic ride a bodyless function; Struct, Union, Pointer, Array, Callback and Alias ride a struct; an `@FFI.Address` function returns `RawPtr` |
| 3200 | error | unknown parent construct | extends must name a declared construct family |
| 3205 | error | construct inheritance cycle | the construct resolves back to itself through its parents |
| 3210 | error | conversion takes one argument | a numeric conversion takes exactly one argument |
| 3214 | error | not callback state | callback state holds a Kira-owned value: scalars, strings, arrays, structs and enums of them, never `Any`, a descriptor, a task or another handle |
| 3215 | error | not a callback-state handle | `nativeUserData` exports a token from the handle `nativeState` returned |
| 3216 | error | recovery without one type | `nativeRecover<T>` names the one type the state is recovered as |
| 3217 | error | recovery from a non-token | `nativeRecover` reads the state a `RawPtr` userdata token names |
| 3218 | error | state recovered as another type | the handle this token was exported from boxes another type than the one recovered |
| 3219 | error | freeing a non-handle | `nativeStateFree` releases through a callback-state handle or a `RawPtr` token |
| 3220 | error | intrinsic arity | a callback-state intrinsic takes exactly one value argument |
| 3221 | error | intrinsic type arguments | only `nativeRecover` takes a type argument |
| 3229 | error | no child slot | trailing child content fills a `some Family` or `[some Family]` slot, and this callee declares none |
| 3231 | error | child slot holds one child | a `some Family` slot takes exactly one child; a list of them is written `[some Family]` |
| 3234 | error | missing required construct member | this construct does not provide a requirement of its family |
| 3242 | error | builder in a single child slot | a `For` or `if` builder produces any number of children, so it fills only a list slot |
| 3243 | error | `@FFI` storage not described | an `@FFI.Array` names an `element` type and a positive `count`, an `@FFI.Alias` names a `target` type, an `@FFI.Array`, `@FFI.Alias` or `@FFI.Callback` declares no fields of its own, and a function given as a callback takes and returns what the callback names |
| 3255 | error | `@Main` in a library | a library is entered by the program that imports it and declares no `@Main` |
| 3274 | error | child slot filled twice | a slot is filled by the trailing block or by a named fill, not both |
| 3275 | error | ambiguous overloaded call | several declarations of the name fit the call's arguments equally well, so the call has no single meaning |
| 3276 | error | init content not last | an `init` takes content in its last parameter only: the children are written after every argument, so one `some X` parameter can hold them |
| 3277 | error | content parameter holds one child | a `some X` parameter takes exactly one child; a `[some X]` parameter takes a list of them |
| 3278 | error | init shadows the header | this `init` takes what the declaration already takes between its parentheses, so a construction fits both |
| 3285 | error | `retains` names no parameter | `retains:` names a parameter of the function whose storage C keeps |
| 3286 | error | `retains` names a parameter twice | each retained parameter is named once |
| 3287 | error | retained argument not moved | C keeps a `retains:` argument's storage past the call, so the caller gives it up with `move` |
| 3288 | error | compiler-known trait declared | `Copyable`, `Drop`, `Send` and `Sync` exist without a declaration |
| 3289 | error | not a trait | a conformance or bound names something that is not a trait |
| 3290 | error | conformance written twice | a type conforms to a trait in exactly one place |
| 3291 | error | associated type unbound | nothing the conforming type presents says what this associated type is |
| 3292 | error | trait requirement missing | the conforming type presents no member for this requirement |
| 3293 | error | member disagrees with its requirement | the member's receiver, parameters and result must match the trait's |
| 3294 | error | member outside the trait | an `extend Type: Trait` block carries only members the trait declares |
| 3298 | error | family claims a compiler-known trait | a construct family has no members of its own to state that fact about |
| 3299 | error | receiver outside a method | only a function declared in a struct takes `self` |
| 3301 | error | `Drop` without `drop(borrow mut self)` | a type claiming `Drop` writes `function drop(borrow mut self)` with no parameters or result |
| 3304 | error | callback state runs a drop body | boxed state outlives the frame that made it and is freed where no engine is running to enter a user `Drop` body; box what the value computes instead |
| 3308 | error | supertrait is not a trait | a supertrait clause names a trait |
| 3309 | error | supertrait cycle | these supertraits require one another in a loop |
| 3310 | error | supertrait not conformed | the type conforms to a trait without conforming to what that trait requires |
| 3315 | error | bound not satisfied | the type argument does not conform to the parameter's bound |
| 3316 | error | type arguments not inferred | the call does not determine every type argument of the generic function; pass them explicitly |
| 3317 | error | module initialization cycle | these module bindings depend on one another without an initial value |
| 3330 | error | main-thread function called directly | a `@MainThread` function is called through `MainThread.invoke`, `MainThread.spawn`, or `MainThread.post` |
| 3331 | error | main-thread request shape | a main-thread request takes one call in its trailing block and no parenthesized arguments |
| 3332 | error | main-thread request needs a direct call | the trailing block holds one direct call to a named function, with no nested trailing block |
| 3333 | error | main-thread request with a mutable borrow | the call's `borrow mut` parameters would reach storage that stays on the requesting context |
| 3334 | error | main-thread spawn result | a spawned main-thread call returns an owned `Send` value or nothing |
| 3335 | error | value cannot cross to the main thread | an argument of a main-thread request is not `Send` |
| 3336 | error | main-thread task handle is opaque | `.await` is the only operation a main-thread task handle has |
| 3337 | error | main-thread entrypoint | the entrypoint runs on the application thread, so it cannot also be `@MainThread` |
| 3345 | error | invalid distinct representation | a distinct representation must resolve to one scalar word |
| 3346 | error | distinct type cycle | this distinct representation resolves back to itself |
| 3347 | error | distinct constructor takes one value | construct the distinct type from one representation value |
| 3348 | error | distinct constructor type mismatch | use a representation value rather than a different nominal type |
| 3350 | error | literal out of range | the literal does not fit the type it is written into |
| 3353 | error | task target borrows a parameter | a task owns its stored arguments and cannot keep a borrowed parameter |
| 3354 | error | async function requires a task | start this async function through Task rather than calling it directly |
| 3360 | warning | `nativeStateFree` is deprecated | it releases one reference, not the state: let the handle go out of scope to release its reference, and pair every `nativeUserData` token with `nativeUserDataRelease` |
| 3361 | error | owner count of a non-token | `nativeUserDataRetain` and `nativeUserDataRelease` take a `RawPtr` userdata token; a handle releases its own reference when it goes out of scope |
| 3362 | error | no value to describe | `.type` describes a value, and this expression has none |
| 3363 | error | not a descriptor member | a runtime type descriptor answers `name`, `package`, `kind`, `arguments` and `conformances`, and nothing else |
| 3364 | error | channel constructor takes no arguments | the channel payload is selected by its type argument |
| 3365 | error | channel payload cannot be carried | channels carry scalars, strings, and structs and enums built from them; a pointer, closure, task or class value cannot cross |
| 3366 | error | send takes one value | send requires the payload crossing the channel |
| 3367 | error | unknown channel operation | this operation is not available on this channel end |
| 3368 | error | kernel service signature | a `@Service` function is a free, non-generic function whose parameters are owned `RawPtr`, `Int` or `U64` values and whose result is one of those or nothing |
| 3369 | error | kernel service body | a `@Service` function names a kernel service the platform runtime implements, so it has no body |
| 3370 | error | move into a copy parameter | a `copy` parameter takes its own copy of the argument, so the argument cannot be written `move` |
| 3371 | error | no tests to run | a test build enters the `kiraTestMain` that a test package's `TestRunner` collector generates, and this program has none |
| 3372 | error | unknown native library | `library:` names a `NativeLibrary` that a package's `nativeLibraries` declares |
| 3373 | error | union literal names two members | an `@FFI.Union`'s members share their storage, so a literal writes at most one |
| 3374 | error | member C cannot lay out | a member of an `@FFI.Struct` is a scalar, a payload-less enum, a `CString`, a distinct of one, or another `@FFI` type; a member of an `@FFI.Union` is one whose bytes C reads as they are, so not an enum or an `@FFI.Array` |
| 3375 | error | unknown pointer ownership | an `@FFI.Pointer`'s `ownership:` is `borrowed`, `unmanaged` or `owned`, and only an owned one names a `free:` function |
| 3376 | error | owned pointer without a free function | an owned `@FFI.Pointer` names in `free:` an `@FFI.Extern` function that takes the pointer, or a `RawPtr`, and returns nothing |
| 3377 | error | `@FFI.Variadic` without `@FFI.Extern` | `@FFI.Variadic` marks an `@FFI.Extern` function, whose declared parameters are the fixed ones; a call passes the rest after them |
| 3378 | error | owned pointer copied | an owned `@FFI.Pointer` is freed once, so it is borrowed or handed over with `move`, never copied |
| 3379 | error | unknown callback context | an `@FFI.Callback`'s `context:` names one of its `params`, written `name: RawPtr`, which C passes back as it was given |
| 3380 | error | capturing lambda without a context | a lambda that captures reaches its captures through the callback's `context:` parameter, which this callback does not name |
| 3381 | error | bit-field C cannot lay out | `@Bits(n)` marks an integer member of an `@FFI.Struct`, from 1 to its type's width bits wide |
| 3382 | error | system call with too many arguments | an `@FFI.Syscall` passes its arguments in registers, of which a Linux system call has six |
| 3383 | error | construct member type not inferred | a construct member written without a type takes the type of its initializer, of the value its block ends with, or the one the wrapper taking it up gives it, and nothing gives this one a type |
| 3384 | error | binding prefix the value cannot take | `borrow` and `copy` bind only a value that binding leaves alone, not an array, an enum, an owned C pointer or what runs a `drop`; `borrow mut` binds nothing, having no caller to write back to |
| 3385 | error | `match` arms disagree | every arm of a `match` used as a value gives a value of one type |
| 3386 | error | `match` arm without a value | an arm of a `match` used as a value is an expression or ends with one, unless it cannot reach its end |
| 3387 | error | pattern of another type | an enum subject is matched by its variants, an integer one by integer literals and a Bool one by `true` and `false` |
| 3390 | error | no structural equality | `==` compares field by field down to the leaves; a task, native state, closure, type descriptor or C storage leaf has no equality of its own |
| 3391 | error | no structural order | `<` and `compare` order field by field down to the leaves; an unsigned integer, a pointer, a handle or C storage leaf has no order the walk can read |
| 3392 | error | no structural hash | `hash` folds the leaves' bits, which must be their value; a float, a pointer, a handle or C storage leaf has none |
| 3393 | error | exit function signature | an `@AtExit` function is a top-level `function name(reason: Int, detail: Int)` with a body and no result |
| 3394 | error | discarded failure | handle the failure, propagate with `try`, or deliberately absorb it; bare Result expressions, `let _` on a Result and unbound Error arms discard it |
| 3395 | error | binding in a multi-pattern arm | an arm with several patterns, `A, B ->`, binds no payload: give each payload its own arm |
| 3396 | error | typed memory without a type | `heapLoad` reads the type it is given, `heapLoad<U32>(pointer, offset)`, or the one its position expects; here there is neither |
| 3397 | error | type has no C memory shape | typed memory holds what C can: an integer, a float, a `Bool`, a `RawPtr`, an enum without payloads, a distinct over one of those, or an `@FFI.Struct`, `@FFI.Union` or `@FFI.Array` |
| 3398 | error | value with a drop copied | a value whose type runs `drop`, itself, through a field or through a case payload, is dropped once, by whoever holds it last: hand it over with `move` or lend it with `borrow` |
| 3399 | error | payload with a drop bound from a named value | an arm binding a payload whose type runs `drop` takes it from the value matched, which would then drop it again: write `match move name` to give the value to the match |
| 3400 | error | Foundation is required here | add `import Foundation` to this file; text literals and value rendering require its runtime declarations |
| 3401 | error | type test on a crossing family | a public family of a library, or a framework's, is a RIDL trait whose values any module may declare: `is` and `as` cannot list them, so ask the value through a member of the family instead |
| 3402 | error | unknown annotation | the name is no built-in attribute, and no macro or property wrapper in scope takes it up: declare one by that name, import the module declaring it, or remove the annotation |
| 3403 | error | annotation does not apply here | this built-in attribute is not written on this kind of declaration; see `docs/subset.md` for where each one goes |
| 3404 | error | private member | the member is written `private`, which keeps it to the declaration writing it and to that file's extensions of its type: use it there, or drop `private` |
| 3405 | error | length change of a crossing array borrow | a `borrow mut [T]` parameter of a public function crosses RIDL as its elements and their count, so its caller never sees a new length: write its elements in place, or pass a struct holding the array, which crosses by address |
| 3406 | error | private family extended from another module | a family its module does not export is an enum of that module's own declarations, so another module cannot join it: write the family `public`, which makes it a RIDL trait any module may declare members of |
| 3407 | error | atomic operand not an integer | an atomic operation works on a value the hardware reads and writes whole: an integer, a sized number such as `N32`, or a `RawPtr`, which only loads, stores and exchanges take |
| 3408 | error | memory ordering not allowed here | the ordering is a `MemoryOrder` case written at the call, and one the operation allows: a load is not `Release` or `AcquireRelease`, a store not `Acquire` or `AcquireRelease`, and a compare-exchange's failure ordering neither `Release` nor `AcquireRelease` nor stronger than its success ordering |
| 3409 | error | system call outside the system | a program reaches the operating system through services, never through system calls of its own: call the service, or, in the package that is the system itself, write `let systemCalls: Bool = true` in its manifest |
| 4001 | error | no package manifest | several files form one program only as the `app/` sources of a package declared in `package.kira` |
| 4002 | error | malformed package manifest | `package.kira` declares `construct Name extends Package { ... }` with typed `let` members |
| 4003 | error | unknown package member | `Package` declares `kind`, `version`, `moduleRoot`, `dependencies`, `nativeLibraries` and `systemCalls`, a dependency takes `name`, `path`, `version`, `url`, `rev` and `tag`, a native library `name`, `binary`, `header`, `klffi`, `linkerFlags`, `linkMode`, `availability`, `headers`, `sources`, `autobind` and `nativeTargets`, and a target row `triple`, `staticLib`, `dynamicLib`, `defines`, `frameworks`, `systemLibs`, `compilerFlags`, `linkerFlags` and `runtimeFiles` |
| 4004 | error | package member has the wrong type | `kind` is a `PackageKind`, `version` and `moduleRoot` are `String`s, `dependencies` is a `[Dependency]` and `nativeLibraries` a `[NativeLibrary]` |
| 4010 | error | no sources in `app/` | a package's Kira sources live in its `app/` directory |
| 4020 | error | dependency has no readable manifest | a path dependency names a directory holding a `package.kira` |
| 4021 | error | dependency cycle | this dependency leads back to a package that depends on it |
| 4022 | error | duplicate dependency | the manifest already declares a dependency with this name |
| 4028 | error | registry dependency | only path dependencies resolve; no registry fetcher is configured |
| 4029 | error | git dependency | only path dependencies resolve; no git fetcher is configured |
| 4033 | error | no library for this import | no dependency in `package.kira`, no package the toolchain bundles and no framework in the `--sdk` SDK has this module name |
| 4034 | error | malformed native library | a `NativeLibrary` names its `name` and a `binary` or `nativeTargets`, each static row has something to link, and no triple has two rows |
| 4035 | error | native library declared twice | every package's native libraries share one namespace |
| 4036 | error | native declarations unreadable | a native library's `klffi` names the `.klffi` file of its `@FFI` declarations, and its `autobind` the C headers to make them from, relative to the package or one of its include directories |
| 4037 | error | native library file missing | the archive, shared library or runtime file a native library's row names for this target is not there |
| 4038 | error | shader build failed | the `ksl` shader driver rejected the shader a `ksl!` call names; its diagnostics come before this one |
| 4039 | error | shader output missing | no `ksl` shader driver is on the path and `generated/shaders` holds nothing for the shader a `ksl!` call names |
| 4040 | error | klist unreadable | a `klist!` call names a `.klist` file relative to its package root, or to the root of the dependency module it names first; the note before this one says which file |
| 4041 | error | malformed klist | the `.klist` file a `klist!` call reads is not klist version 1; the note before this one names the line and what is wrong |
| 4042 | error | klist value missing | the key path a `klist!` call names, dict keys and array indexes separated by dots, names no value in the file, or names a dict |
| 4043 | error | malformed klist call | `klist!` takes a path and a key path, both string literals: `klist!("Info.klist", "BundleVersion")`, with a dependency's module name first to read from that package |
| 4044 | error | framework contract unreadable | a framework in the SDK holds its contract as the `.ridl` files under `Resources/`; this one has none, one that does not parse, or imports a module no framework in the SDK provides |
| 4045 | error | unknown platform | `import Name on ...` names the platforms a file takes part on as `Build.platform()` spells them: `tessera`, `ios`, `macos`, `windows`, `android`, `linux`, `web` or `unknown`, separated by commas |
| 4046 | error | platform import after a declaration | a file with an `import ... on` is left out of a build for any other platform without being read past its imports, so every import in it comes before its first declaration |
| 5001 | error | unknown macro | no macro by this name is declared where it is used |
| 5006 | error | unknown macro kind | `kind { … }` names one of `function`, `attribute`, `derive`, `wrapper` or `collector` |
| 5007 | error | macro does not apply here | the macro's `appliesTo` does not list this kind of declaration |
| 5008 | error | appliesTo misplaced | a macro that annotates declarations lists the kinds it is legal on with `appliesTo`, and a `function` or `collector` macro lists none |
| 5010 | error | macro expansion too deep | macros kept expanding into further macro uses past the limit, which a macro that produces itself never leaves |
| 5011 | error | not a derive macro | `@Derive(X)` names a macro that exists but is not a derive. A derive is declared `comptime macro X { kind { derive } }`; a macro declared with kind `function`, `attribute`, `wrapper` or `collector` answers a use of itself, not a position in an attribute's list. Check the `kind` on X's declaration, or use X the way it is declared. |
| 5012 | error | expand signature | a `comptime macro` defines `expand`, taking one value per thing its kind hands it |
| 5013 | error | no such macro | no `comptime macro` by this name is visible here at all, so nothing was rejected for being the wrong kind. A macro is visible only in the file that declares it and in files that `import` the module declaring it; another file's import does not carry over. Foundation is merged into every package, so its derives — Equatable, Clone, Hashable, Lerp, Ordered, Serializable, Tagged — need no import. `Copy` is not a macro: the compiler handles it and records an assertion. A name that was two derives once is now one: `Serializable` generates `serialize_T` and `deserialize_T` together, so listing `Deserializable` beside it is the usual way to land here. |
| 5014 | error | a derive macro is not used bare | this name IS a derive macro — it is declared `kind { derive }` — but it was written as an annotation of its own. A derive is named inside the derive list, not applied directly: `@Derive(Exploding)`, and where a form takes several, `@Derive(Equatable, Exploding)`. A macro of kind `attribute` is the one that answers a bare `@Name`. |
| 5021 | error | macro reported an error | the macro's body called `Diagnostics.error`, so its expansion is discarded |
| 5025 | error | no such field | `Syntax.replaceField` or `Syntax.dropField` named a field the declaration does not have |
| 5028 | error | two replacers | two macros rewrite the same declaration, and the second would have no original left to observe |
| 5029 | error | trigger without replace | a macro a field annotation summons rewrites the declaration carrying the field, so it declares `replace { true }` |
| 5030 | error | compile-time macro evaluation failed | the derive or macro could not produce syntax; inspect its reported diagnostics and ensure its input types are supported |
| 5031 | error | the macro body failed while running | the macro was found, its signature matched, and its body was compiled and started — it is the RUN that failed. The body runs as a program of its own on the VM under a fixed budget (500,000,000 steps, 1 GiB), so this is a trap inside the body rather than a syntax problem in what it was handed: an unwrap of nothing, an array index out of range, a division by zero, an exhaustive match over a value the body did not expect, or the budget running out. `Diagnostics.error(...)` in the body reports 5021 with what the body said instead, which names the field or case it wanted. |
| 5032 | error | the macro produced unreadable syntax | the body ran to completion but what it returned is not syntax the compiler can read back. A `quote` that yields nothing, a fragment that does not stand on its own, or a body that returned a value rather than quoted syntax lands here. The expansion is discarded and nothing of it is used. |
| 5033 | error | the macro body did not compile | the wrapper the compiler builds around the macro body was checked and the macro's own entry point did not survive it, so nothing ran. The body is checked as a program of its own with only what its kind hands it: a `function` macro's `expand` takes the `Syntax` it was used on, a `derive` macro's takes the `Declaration` it was written on. A body referring to anything outside those — a name from the file that used it, a Foundation helper it did not import — is not in scope there, and a signature that does not match its kind is 5012. |
| 5034 | error | a wrapped property needs a type | a field a generic struct wraps is stored as that struct's instance for the field's type, `@State var count: Number = 0` as a `State<Number>`, so the field is written with its type |
| 5035 | error | a wrapper argument needs a label | an argument with no label sets a generic wrapper's next field after `wrappedValue` and `key`, and this one has none left to set: write `@Wrapper(field: value)` |
| 5036 | error | the macro's program was read without its bodies | a build first reads the packages built apart without their bodies and takes every macro's answer from an earlier build. A macro no earlier build answered needs the bodies it runs, so the build reads the program again with them and expands it anew; this code never ends a build. |
| 6001 | warning | global mutable state | put state in a value created at the entry point and pass it by mutable borrow; a framework, built with `--emit shared` or `--emit ridl`, keeps its process state in a top-level `var`, since no RIDL call carries it; a `@ThreadLocal var` is each thread's own |
| 6002 | warning | prefixed declaration name | use the package namespace, a type method or a namespaced constant instead of a short prefix |
| 6003 | warning | integer code comparison | decode the raw code into an enum at the boundary and match on its cases |
| 6004 | warning | comparison chain | match on the value instead of comparing it in an if/else-if chain |
| 6005 | warning | counted while loop | use a for range or iterate over the collection |
| 6006 | warning | flag-controlled loop | use while true and leave with break or return |
| 6007 | warning | fallback over an owned enum | list every case of an enum this package owns so new cases require a decision |
| 9001 | error | outside the supported subset | kira does not compile this construct yet; see docs/subset.md |

<!-- hand-written: diagnostic standards -->

## Standards

Normative for every diagnostic klf-kira reports, from the Kira front end and
from the framework stages that run for it (unit merge, lowering, FFI and
autobind, linking). `tools/generate-diagnostics.py` keeps this section when it
rewrites the table above. The audit of the current state is in
`docs/diagnostics-audit.md`.

### Anatomy of a diagnostic

Every diagnostic has:

1. **A stable code.** `KLF-` plus a name for framework codes; a number from the
   table above for Kira codes. A code is never reused for another meaning, and
   a new code goes through the table procedure (`definitions/language.klfd`,
   then `tools/generate-diagnostics.py`).
2. **A headline in plain words that names the user's symbols.** The name is the
   source name, fully qualified when two units could mean different things. A
   mangled or internal name is never shown: a generic instance is written with
   its arguments (`textOf<Array<UN8>>`), and a generic enum's instance number
   is dropped (`ApprovalGate`, not `ApprovalGate_G1876825535242`). Where the
   headline cannot name the symbol, the primary label does.
3. **A primary span with a caret label** that says what is wrong *here*. The
   carets cover the offending range, or the identifier the diagnostic is about.
4. **Secondary spans with labels** for the related places: the other
   declaration in a conflict, the trait a conformance misses, the conflicting
   import, the generated-file origin. Each is a `:::` excerpt.
5. **`= note:` lines for facts**: which units or packages are involved and by
   name, what differs and how, and what the compiler concluded.
6. **`= help:` lines with a concrete next step** whenever one exists: a
   did-you-mean for a misspelled name, the missing `import`, the missing
   conformance, the missing `public`, the `@FFI.Extern` library to declare.

### Rendering

The house style is Rust's. A diagnostic prints in this order:

```
error[3061]: call to an undefined function `missingThing`
 --> app/main.kira:5:21
  |
5 |     let x: String = missingThing(3)
  |                     ^^^^^^^^^^^^ no function with this name is declared
  = note: ...
  = help: ...
```

- The headline is `error[CODE]: ` followed by the headline. A warning reads
  `warning[CODE]:`; a note reads `note[CODE]:`.
- The primary place is `-->`, a secondary place is `:::`. Each excerpt has
  the gutter line `|`, the numbered source line, and the caret line.
- The gutter widens to the widest line number shown.
- Notes and helps follow the excerpts, one per line, in the order written.
- A message that already carries its notes and helps as `= note: ...` and
  `= help: ...` lines is split by `klf_services::split_message`; an unindented
  line after a note continues it.

`klf_services::snippet` is the one renderer. Both the runtime records a
definition reports (`klf_defsvc::report`) and the session's `Diagnostic`s
(`klf-cli` `render`) go through it, so a diagnostic reads the same whichever
stage raised it.

### Generated code

An error inside generated code (autobind bindings, derives, macros, a
header-generated binding file) traces back to its origin (illustrative):

```
error[3183]: argument type mismatch
 --> bindings/Network.kira#generated337:14:9
  = note: this declaration was generated from `include/net.h` line 88
  = note: the generator skipped `struct sockaddr_storage` because it has a
          flexible array member
  = help: declare the parameter with `@FFI.Struct` in the package
```

A generated file is named by its origin with `#generated<n>`. The renderer
shows the origin line when the origin is known. Where the generator dropped
a declaration, the note says what it dropped and why.

### Cross-unit errors

A diagnostic that involves two units names both units, and each unit's
declaration is written as a `:::` place with its file and line. A conflict
that is the compiler's own fault (two lowerings of one definition that disagree)
says so in a help line and names the unit that lowered it.

### RIDL errors

A RIDL error names the module, the type, the member, and the other side's
version or shape: `module Network, type Socket, member send: the contract has
`send(Bytes) -> Number`, the implementation has `send(Bytes, Number) -> Number``.

### Runtime traps

A trap prints the source location and a named reason, in the same shape as a
compile error (illustrative shape; the runtime's own trap codes are listed in
the framework's KLF-RT table). Never an opaque `KLF-RT-0001`:

```
panic[KLF-RT-0007]: index 4 is out of range for an array of 3 elements
 --> app/main.kira:12:9
  |
12 |         items[4]
  |         ^^^^^^^^ the index is taken here
```

### Naming rules for messages

- Source names, never internal ones. Strip `_G<n>`, `#<n>`, the `$` of a
  generic instance, and any unit suffix from the headline.
- A message that names a symbol quotes it with backticks: `` `name` ``.
- Counts, sizes and indices are written in plain numbers.
- A message says what the user wrote, not how the compiler represents it.

### Codes that name nothing

A code whose message does not yet name its symbol is listed in
`docs/diagnostics-audit.md` under "missing symbol name". The renderer quotes
the identifier under the primary span when that span is one, so such a code
gains its name as soon as its report site points at the name.
