# ksl

KSL, Kira's shader language, as a KLF `ShaderLanguage` definition. The
definition parses and checks a `.ksl` file and its imports, then lowers it to
one KSIR module through the `klf.shader.*` services. The kernel validates the
module, assigns binding slots and writes MSL, SPIR-V, HLSL, GLSL 4.30 and
WGSL, plus a `.resources` digest (`KLF-KSL.md`).

The semantics follow the oracle's `kira/crates/kira-ksl-*`. `docs/diagnostics.md`
lists every code.

## Build and use

```sh
klf build definitions/shaders/ksl -o ksl   # the ksl driver
ksl build Shaders/UiRect.ksl --out generated/shaders
ksl build UiRect.ksl --target wgsl --emit source
ksl build UiRect.ksl --target ksl --emit source   # back to KSL, through the out
kmsl build Blit.metal --target ksl --emit source  # MSL to KSL
ksl check Shaders
```

The binary also holds every other bundled shader definition, so `kmsl` and
`ksl` are the same file under two names (`KLF-KSL.md` 5.9).

`ksl --help` lists the flags: `--overrides`, `--bounds`, `--debug-info`,
`--diagnostics json` and the target versions.

## Layout

- `definitions/language.klfd`: the `Ksl` construct, its diagnostic specs and
  kernel keys, and the four phases.
- `definitions/syntax/`: the lexer, the syntax tree, and a parser that stops
  at the first error.
- `definitions/package/loader.klfd`: reads the compiled file and every file it
  imports.
- `definitions/semantics/`: the checker. It reports every independent error,
  and a failed expression takes `Void` so that it is not reported again.
- `definitions/lowering/`: the KSIR module. Types and KSL packing, globals and
  the shader declaration, functions and statements, expressions, built-ins.
- `definitions/out/`: the out, which writes a unit of any shader language
  back as KSL (`KLF-KSL.md` 22.9), and refuses what KSL cannot spell.
- `corpus/`: cases `klf test definitions/shaders/ksl` runs.

## Behavior

- **Imports:** `import A.B` reads `A/B.ksl` beside the importing file, then
  under the library root. `library/` ships `Shape` (`sdRound`,
  `smoothUnion`); `klf build definitions/shaders/ksl --out DIR` copies it to
  `DIR/share/ksl/library`. Each path segment matches ignoring ASCII case,
  as in the oracle. Everything an imported file declares is named `B_name`, and the
  importer writes it as `B.name`.
- **Enums:** an enum is a namespace of `Int` constants.
- **Constants:** a literal or named constant takes the scalar type its
  position expects. Integers become `Int`, `UInt` or `Float`; nothing else
  becomes `Bool`.
- **Packing:** every struct is laid out explicitly, stage interfaces too, so
  reflection reports each one as the oracle does. Scalars take 4 bytes, 2-wide vectors 8, 3- and 4-wide vectors
  16, and matrices 16 per column. A nested struct takes its uniform size and
  aligns to at least 16. A storage array steps by its element's storage size.
- **Stages:** every member of a stage's input or output struct that is not a
  built-in takes the next location. Integer members are flat unless the
  member says otherwise.
- **Sampling:** every `sample` reads mip level zero, as the oracle's WGSL
  does. It therefore means the same in every stage and under any control
  flow.
- **Textures:** a `write` or `read_write` texture is an `rgba8unorm` storage
  image, or `r32uint` for `Texture2dUint`. `read_write` needs the
  `storage-image-read-write` capability, which the definition declares.
- **Options:** each option is an override. `--overrides keep` leaves options
  for the host to specialize.

## Verification

The 38 KSL files of `ember`, `ui-foundation` and `kcoreanimation`
build. For each of their 34 shaders, the `.resources` digest is byte for
byte the oracle's (`kira shader build`), and so is the `KSLR1` reflection
for every target once KLF's `source`, `spec` and `rename` records are
removed. The 63 SPIR-V modules pass `spirv-val`, and the 63 WGSL modules
pass naga.
