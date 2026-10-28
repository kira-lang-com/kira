# msl (`kmsl`)

`kmsl` takes Metal Shading Language to SPIR-V, HLSL, GLSL 4.30, WGSL and
MSL. It is one of the shader definitions bundled with the Kira Language
Framework: the frontend is written in KLF Kira, and the framework builds it
into a native driver. Every backend is the framework's; the definition
parses and checks a subset of MSL and lowers it to KSIR, the framework's
shader IR.

The specification is section 23 of `roadmap/KLF-KSL.md`. Decisions
particular to this frontend are D-350 to D-353 in `docs/decisions.md`.

## Building

From the framework's root:

```
export PATH=$HOME/.cargo/bin:$PATH
./target/release/klf build definitions/shaders/msl -o /tmp/kmsl/kmsl     # the driver alone
./target/release/klf build definitions/shaders/msl --out /tmp/kmsl-root  # a sysroot
./target/release/klf test definitions/shaders/msl                        # the corpus
```

## Using

```
kmsl build Blur.metal --out generated                 # every target
kmsl build Blur.metal --target spirv,wgsl --out generated
kmsl build Reduce.metal --override scale=2 --out generated
kmsl build Reduce.metal --overrides keep --out generated
kmsl check Shaders/
```

One file is one shader, named after the file stem: one `kernel`, or at
most one `vertex` and one `fragment` function. `kmsl --help` lists the flags.

## The subset

Accepted: `#include <metal_stdlib>`, local includes, object-like `#define`
and conditionals; scalar, vector, matrix, packed and array types, `half`;
structs; free functions, `thread` and `threadgroup` references, function
templates deduced from their arguments, namespaces; the texture and sampler
types with `sample`, `sample_compare`, `gather`, `read`, `write` and the size
queries; relaxed atomics; `threadgroup_barrier`; `discard_fragment`;
function constants.

Refused, each with its own code: pointer arithmetic, stored pointers,
argument buffers, function tables and ray tracing, mesh and object shaders,
tile functions, SIMD-group functions, class templates, lambdas,
`constexpr sampler`, `printf`, recursion, and a `switch` case that falls
through after doing something. `docs/diagnostics.md` lists every code.

## How MSL maps

- Every resource goes in one group, buffers first, then textures, then
  samplers, each by Metal index, and keeps its Metal index for MSL output.
- A helper that takes a `device` or `constant` pointer is lowered once for
  each set of resources its callers pass it.
- A kernel's workgroup size is three overrides, `workgroup_size_x`, `_y` and
  `_z` (ids 65533 to 65535, default 1), since Metal sets it when encoding a
  dispatch. `[[threads_per_threadgroup]]` reads them.
- A function constant is an override with no default. Give it a value with
  `--override`, or keep it with `--overrides keep`.
- `[[user(name)]]` members, and stage members with no attribute, get
  locations by name, so a vertex output and a fragment input match.
- `write` and `read_write` textures are storage images of `rgba8unorm`,
  `r32uint` or `r32sint`, by texel type.

## Layout

- `definitions/syntax`: the preprocessor, lexer and parser.
- `definitions/semantics`: name resolution, types, overloads, templates and
  the checks.
- `definitions/lowering`: KSIR through the framework's `klf.shader` services.
- `corpus`: accepted shaders and one refused shader per diagnostic.
