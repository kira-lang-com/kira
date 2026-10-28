# Standard packages

Packages the toolchain bundles. A program imports them by name, with no manifest entry.

| Package | Role | Built as |
| --- | --- | --- |
| `Foundation` | the standard library every program may import | the sysroot unit, with `Heap` |
| `Heap` | raw memory under Foundation | the sysroot unit |
| `Archive` | archive formats, starting with ar | its own unit, per importing program |
| `Build` | the build system behind `kira build` | its own unit, per importing program |
| `Elf` | ELF reading | its own unit, per importing program |
| `Kten` | the Kten value format, text and binary | its own unit, per importing program |
| `Network` | sockets, resolver and the network stack over Foundation | its own unit, per importing program |
| `Seyoul` | async I/O, timers and tasks | its own unit, per importing program |

The sysroot compiles only `Foundation` and the packages it reaches by path. The others are installed beside it and built as their own units by each program that imports them. See `Build/DESIGN.md` and `Network/DESIGN.md`.
