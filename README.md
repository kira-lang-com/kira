# Kira

Kira, hosted on the Kira Language Framework (KLF-RIDL section 27: `name =
"kira"`, `driver = "kira"`, `extensions = ["kira"]`, `memory = .Affine`,
`exclusivity = .Static`, `convention = .Ridl`). The compiler is written as
`.klfd` definitions in KLF Kira; the framework in `../kira-language-framework`
loads them and builds the native `kira` driver from them.

The reference for Kira's syntax and meaning is the Rust implementation in
`../kira`. kira compiles a subset of it, listed in `docs/subset.md`.

## What's here

This repository defines two languages, each a definition package under
`languages/<name>/`, listed in the root `toolchain.klfd`:

- `languages/kira/` is Kira.
  - `definitions/` holds the definition: `language.klfd` (the `Kira` construct,
    its diagnostic list and the four phases), `diagnostics.klfd`, and the
    `package/` (manifest and loading), `syntax/`, `semantics/` and `lowering/`
    folders.
  - `std/Heap/` wraps the shared KIR raw allocator. `std/Foundation/` defines
    source-level `Optional` and `Result` and uses the heap package for
    allocation.
  - `examples/<name>/main.kira` holds one program per directory.
  - `corpus/` holds the regression cases `klf test` runs: `core` and `examples`
    build and run programs, `syntax` and `semantics` check rejected programs
    against their diagnostic codes, `packages` builds packages with libraries
    from `corpus/packages/`, and `ffi` and `ffi-diagnostics` call C through the
    `.klffi` forms.
  - `tests/` and `tests-ffi/` hold the harness ported from `../kira`.
  - `docs/` has `subset.md` (what kira accepts) and `diagnostics.md`.
- `languages/ksl/` is KSL, Kira's shading language, with its `definitions/`,
  `library/`, `corpus/`, `tests/` and `docs/`.
- `toolchain.klfd` lists both languages and what an installed toolchain of each
  carries. `knvm binstall` reads it.
- `tools/` holds `knvm`, the version manager, and `launcher`, the one binary
  installed on PATH under each compiler's name. `tools/knvm/README.md` has the
  layout and the verbs.
- `roadmap/ROADMAP.md` records the Kira-in-KLFD status and the KLF M7 exit
  criteria.

## How it runs

A program is a package: `package.kira`, a `construct ... extends Package`
declaration, beside an `app/` directory whose files
form one module, and `import` for the libraries the manifest lists
(`docs/subset.md`). The whole package is one unit. `parse` finds the package,
then lexes and parses every `app/` file and every imported library into one
syntax tree. `elaborate` resolves names
and checks types into a checked program. `lower` builds a `KirModule` from the
checked program through the kernel's builder services. Each phase hands its
result to the next as a definition-owned artifact.

## Setting up

One command, nothing else to install first:

```sh
curl -fsSL https://github.com/kira-lang-com/kira/releases/latest/download/install.sh | sh
```

```powershell
irm https://github.com/kira-lang-com/kira/releases/latest/download/install.ps1 | iex
```

It fetches `knvm` for the machine and runs `knvm setup`: the newest `klf`
with its `klf setup`, which adds the RIDL LLVM it links with; the newest
release of every language; and `knvm` with a launcher per compiler, on PATH.
Run it again, or `knvm setup`, to bring everything up to date. CI publishes
the releases from `.github/workflows/release.yml` on a `v<version>` tag.

From the framework checkout:

```sh
klf check ../klf-kira/languages/kira               # load and compile the definition
klf build ../klf-kira/languages/kira -o kira       # link the native driver
klf build ../klf-kira/languages/ksl -o ksl         # the shading language
```

From this checkout:

```sh
knvm binstall                                      # build, register and install every language
knvm sinstall                                      # knvm and a launcher per compiler onto PATH
kira languages/kira/examples/fibonacci/main.kira -o fib
kira languages/kira/corpus/packages/shop -o shop
klf test languages/kira                            # run every corpus
```

## The commands

The driver is `kira`. `kira help` lists these; `kira help <subcommand>` is
the detail.

- `kira build <sources>` — compile. The default when a command is left out,
  and `-o` names the output. `--emit` says what to write (`.kir`, `.klbc`, `.a`,
  `.ridl`, `.so`); without either, `-o`'s extension decides.
- `kira run <sources>` — build an executable and run it. Everything after `--`
  is the program's own arguments.
- `kira check <sources>` — report diagnostics and write nothing. Given no
  path, the package in the current directory.
- `kira test <package>` — run the `@Test` functions under the package's
  `tests/`. `kira test languages/kira` runs the corpus inside the definition
  itself.
- `kira format <sources>` — format in place. `--check` lists what is not
  formatted instead; `--width`, `--tabSize` and `--tabs` are the shape.
- `kira lsp` — the language server, on standard input and output, for `.kira`,
  `.klfd` and `.ridl`.

The standard library bundles `Foundation`, which carries the test support, and
`Heap`. Test builds load `Test` and its runner without copying harness files.
See [Idiomatic Kira](languages/kira/docs/idiomatic-kira.md) for the intended
style. Regenerate diagnostic references with `python3 tools/generate-diagnostics.py`;
use `--check` to detect drift.

`klf` is the framework's own driver and takes the same verbs for definition
packages, plus `dist`, `kir`, `ridl`, `abi` and `ffi`.
```
