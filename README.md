<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/KiraBannerDark.png">
  <source media="(prefers-color-scheme: light)" srcset="Images/KiraBannerLight.png">
  <img alt="Kira" src="Images/KiraBannerDark.png">
</picture>

# Kira

Kira is a compiled, statically typed, multi-target programming language built in Swift.
This repository contains:

- `KiraCompiler`: lexer → parser → construct pass → type checker → IR → codegen/bytecode
- `KiraVM`: bytecode virtual machine for `@Runtime` functions
- `kira`: CLI (build/run/watch/doc/bindgen/package/lsp)
- `kira-lsp`: Language Server Protocol implementation over stdio JSON-RPC

## Build

```sh
swift build
swift test
```

## CLI

```sh
.build/debug/kira version
.build/debug/kira new HelloKira
cd HelloKira
../.build/debug/kira run
```

`print(value)` is available as a built-in (prints one value per call).

## License

Apache License 2.0 with a Runtime Library Exception. See `LICENSE`.
