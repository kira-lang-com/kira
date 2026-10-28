# kmsl diagnostics

kmsl prints an error as `error[N]` and a warning as `warning[N]`. The
spelling `KMSL-E<NNNN>` names error N, and `KMSL-W<NNNN>` names warning
N - 5000: the kernel's diagnostic channel carries one integer, so a warning
is 5000 plus its number. A message is the title, a colon, and the meaning.
With `--diagnostics json`, N is the `code` field.

Codes 230 to 237 and 5001 come from the shader kernel (KLF spec §23, §16.6).
kmsl maps each kernel key to its code in `definitions/language.klfd`.

## Preprocessing and parsing

| Code | Name | Title | Meaning |
|---|---|---|---|
| 1 | KMSL-E0001 | unexpected token | a token appeared where the grammar allows something else |
| 2 | KMSL-E0002 | expected a declaration | a file holds structs, functions, templates, namespaces and program-scope constants |
| 3 | KMSL-E0003 | unterminated comment or string | the file ends inside a block comment or a string literal |
| 4 | KMSL-E0004 | malformed literal | the number is malformed, out of range, or a kind the subset does not accept |
| 5 | KMSL-E0005 | unsupported directive | the subset preprocesses `#include`, object-like `#define`, `#undef`, `#if` and its kin, `#error` and `#pragma once` |
| 6 | KMSL-E0006 | unknown header | only `<metal_stdlib>` and `<simd/simd.h>` are system headers here |
| 7 | KMSL-E0007 | missing include | no file of that name exists beside the including file |
| 8 | KMSL-E0008 | unbalanced conditional | an `#else`, `#elif` or `#endif` has no `#if`, or an `#if` has no `#endif` |
| 9 | KMSL-E0009 | bad condition | an `#if` condition is an integer expression over defined names |
| 10 | KMSL-E0010 | #error | preprocessing reached an `#error` directive |
| 11 | KMSL-E0011 | includes nest too deep | includes nest more than 32 deep, which an include cycle does |

## Outside the subset

| Code | Name | Title | Meaning |
|---|---|---|---|
| 101 | KMSL-E0101 | kernel beside graphics entries | a file is one shader, graphics or compute, so it cannot hold a `kernel` and `vertex` or `fragment` functions |
| 102 | KMSL-E0102 | graphics entries | a graphics file holds at most one `vertex` and one `fragment` function |
| 103 | KMSL-E0103 | compute entries | a compute file holds exactly one `kernel` function |
| 104 | KMSL-E0104 | pointer arithmetic | pointers are indexed with `[]`; they are not added to, subtracted or compared |
| 105 | KMSL-E0105 | stored pointer | a pointer or reference cannot be held in a variable or a struct member |
| 106 | KMSL-E0106 | buffer not from an entry | a `device` or `constant` pointer passed to a function must be an entry point's buffer |
| 107 | KMSL-E0107 | argument buffer | argument buffers and `[[id(n)]]` are not in the subset |
| 108 | KMSL-E0108 | function table or ray tracing | function tables, intersection functions and ray tracing are not in the subset |
| 109 | KMSL-E0109 | mesh or object shader | mesh and object functions are not in the subset |
| 110 | KMSL-E0110 | tile function | imageblocks, tile functions and raster order groups are not in the subset |
| 111 | KMSL-E0111 | SIMD-group operation | `simdgroup` matrices and `simd_*` functions are not in the subset |
| 112 | KMSL-E0112 | function constant gates a parameter | a function constant cannot decide whether a parameter exists or whether it is defined |
| 113 | KMSL-E0113 | class template | only function templates whose arguments are deduced are in the subset |
| 114 | KMSL-E0114 | lambda | lambdas are not in the subset |
| 115 | KMSL-E0115 | constexpr sampler | a sampler is an entry point argument; `constexpr sampler` is not in the subset |
| 116 | KMSL-E0116 | printf | `printf` is not in the subset |
| 117 | KMSL-E0117 | recursive call | a function reaches itself through its calls, which no shader target can run |
| 118 | KMSL-E0118 | unsupported type | the type is not in the subset |
| 119 | KMSL-E0119 | unsupported struct | a struct holds data members only: no methods, base classes, bit-fields or access specifiers |
| 120 | KMSL-E0120 | unsupported attribute | the attribute is unknown, or not in the subset, or not allowed where it is written |
| 121 | KMSL-E0121 | unsupported function | the library function has no counterpart in KSIR |
| 122 | KMSL-E0122 | unsupported statement | the statement is not in the subset |
| 123 | KMSL-E0123 | fall-through | only a `case` with an empty body may fall through to the next |
| 124 | KMSL-E0124 | memory order | atomics take `memory_order_relaxed` |
| 125 | KMSL-E0125 | unsupported construct | the construct is valid C++ but not in the subset |
| 126 | KMSL-E0126 | no entry point | the file declares no `vertex`, `fragment` or `kernel` function |

## Checking

| Code | Name | Title | Meaning |
|---|---|---|---|
| 201 | KMSL-E0201 | unknown type | the written type names no built-in type, struct or alias |
| 202 | KMSL-E0202 | unknown name | the name is bound to no variable, constant or function declared before it |
| 203 | KMSL-E0203 | redeclaration | two declarations claim the same name in one scope |
| 204 | KMSL-E0204 | type mismatch | no implicit conversion takes the value to the type its position needs |
| 205 | KMSL-E0205 | wrong argument count | the call or construction passes a different number of values than it takes |
| 206 | KMSL-E0206 | no such member | the member does not exist on the type it is read from |
| 207 | KMSL-E0207 | no matching function | no function of that name accepts these arguments |
| 208 | KMSL-E0208 | ambiguous call | two functions accept these arguments equally well |
| 209 | KMSL-E0209 | not assignable | the target is constant, read-only memory, or not a place |
| 210 | KMSL-E0210 | bad entry parameter | an entry parameter is a buffer, texture or sampler with its slot, `[[stage_in]]`, or a built-in its stage provides |
| 211 | KMSL-E0211 | bad stage interface | every member of a stage input or output carries an attribute its stage and direction allow |
| 212 | KMSL-E0212 | slot conflict | two entries use one slot for different resources |
| 213 | KMSL-E0213 | not a constant | the value must be an integer known when the shader is compiled |
| 214 | KMSL-E0214 | missing return | the function can finish without returning its result |
| 215 | KMSL-E0215 | break or continue outside a loop | `break` leaves a loop or switch and `continue` a loop |
| 216 | KMSL-E0216 | template arguments not deduced | every template parameter is deduced from the call's arguments, consistently |
| 217 | KMSL-E0217 | operator does not apply | the operator does not accept these operand types |
| 218 | KMSL-E0218 | duplicate case | two cases of one switch have the same value |
| 219 | KMSL-E0219 | wrong stage | the operation is not available in the stage that reaches it |
| 220 | KMSL-E0220 | bad threadgroup variable | a `threadgroup` variable is declared in a kernel's body, without an initializer |

## Kernel refusals

| Code | Name | Title | Meaning |
|---|---|---|---|
| 230 | KMSL-E0230 | target unsupported | a requested target cannot express this shader |
| 231 | KMSL-E0231 | function constant missing | a function constant has no value: supply one with `--override` |
| 232 | KMSL-E0232 | function constant unsupported | the target cannot specialize a function constant; bake it |
| 233 | KMSL-E0233 | index not constant | the index must be known when the shader is compiled |
| 234 | KMSL-E0234 | stage interface mismatch | a fragment input is not a vertex output of the same location, type and interpolation |
| 235 | KMSL-E0235 | slot collision | two resources take the same slot |
| 236 | KMSL-E0236 | constant not finite | a constant does not evaluate to a finite value |
| 237 | KMSL-E0237 | capability unsupported | the shader uses a capability the target lacks |

## Warnings

| Code | Name | Title | Meaning |
|---|---|---|---|
| 5001 | KMSL-W0001 | non-uniform control flow | a barrier, derivative or implicit-level sample is reached under control flow that varies across invocations |
