# Testing in Kira

Status: design, normative for the migration. The compiler rule in section 3
is implemented in `definitions/package/loader.klfd`. This document is the one
testing style; the old `construct X() extends Test` style is retired.

## 1. `@Test`

A test is a top-level function marked `@Test`:

- no parameters, no return value;
- it passes when it returns with every expectation it reached held;
- it runs in its own child process under `kira test`;
- a failed expectation does not stop the test, so one run reports them all.

Assertions inside a test:

- `expect!(condition)`: records a failure when `condition` is false. A top-level
  `==` in the condition reports both sides and their values.
- `expectEqual!(a, b, left, right)`: the form `expect!(a == b)` expands to.

Behaviour the old style expressed with `expect { ... }` and `Skip`:

- A comparison of values: `expect!(got == expected)`.
- A value that must be an error rendering: compare the rendered string.
- An expected runtime trap (`expect { .Error(.Runtime(...)) }`): not part of
  `@Test` yet. Such tests are kept, and their files are listed in
  `karc-work/testing-baseline/ledger.txt` under "Expected-trap sites"; they
  are not silently dropped.
- Skipping: a test that cannot run on the target is left out of the package's
  `tests/` tree rather than marked.

## 2. Assertions

Only `expect!` and `expectEqual!` are provided. Add a new assertion only when
a migrated test cannot be written honestly with them.

## 3. The `tests/` directory

- `<package>/tests/**/*.kira` belongs to the package's own namespace in test
  builds only (`kira test`, `kira check --test`).
- Normal builds never read `tests/`.
- No separate `package.kira` and no `import Package`. Test files see the
  package's declarations, private ones included, because they share the
  package namespace.
- The tree mirrors `app/`: `tests/<same folders>/<Subject>.kira`.
- Only the package being tested gets its `tests/` read. Dependencies are not
  affected.
- Old `tests/<name>_kik` sub-packages (their own `package.kira` and `app/`)
  are retired: their sources move into the owning package's `tests/`.

## 4. Naming

- One test file per subject under `tests/`, named for the subject. No `Tests`
  suffix, no `Part N` splits, no file-name prefixes to avoid collisions.
- Tests are named for the behaviour they check.
- Tests share the package namespace. A name collision is resolved by grouping
  tests in a namespace or type per subject, not by a prefix.

## 5. Diagnostics

Misuse of the rule (a `@Test` with parameters or a return value, a `tests/`
file that declares a package manifest, and similar) is reported with a
diagnostic code in the diagnostics table of the compiler. The codes are added
with the loader change; none are assigned in this document yet.
