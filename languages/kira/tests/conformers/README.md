# Conformer fixtures

Multi-unit programs for the program-wide conformer set (`docs/conformers.md`).
Each package is built apart as its own unit, and the `App` program links them.

- `Gate` declares the trait `Gate` and a function that dispatches through it.
- `Grant` and `Refuse` each conform one struct to `Gate`. Neither depends on
  the other, so each unit sees only its own conformer.
- `App` depends on all three and holds a `Gate` value of each conformer.

Expected: `kira check conformers/App` passes. Before the program-wide conformer
set lands it fails with `KLF-KIR-9002` ("declares `Gate_G<n>` differently in two
units"), because `Grant` and `Refuse` each build the `Gate` enum with different
cases.
