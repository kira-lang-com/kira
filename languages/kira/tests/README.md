# The Kira test suite

`tests/app` is this language's own test suite, run by the compiler built from
this repository. Use the runner's summary for the current test count.

```sh
cd languages/kira
kira test tests
```

`kira test` builds the package, then drives the test binary through Kira's
test protocol (`list`, `expect`, `check`, `body`) one child process per step,
and prints `ok`, `FAIL` and `skip` lines and the summary. A failing case makes
the command exit nonzero.

## Writing a test

A test is a top-level function marked `@Test`, and `expect!` checks a
condition inside it. Both come from Foundation.

```kira
@Test
function sumsRange() {
    var sum = 0
    for value in 0..5 { sum += value }
    expect!(sum == 10)
}
```

A failed expectation does not stop the test, so `FAIL` lists every one that
failed. A side of an `==` shows its value: `expectation failed: (sum → 9) ==
10`. The older `Test` family form, whose `test` returns a value that `expect`
names, is still what the harness cases are written in, and it is the only form
that can expect a trap.

`kira check --test tests` is the same sources without running them: it writes
nothing and reports every diagnostic rather than the first. Use it while
changing a declaration, and `kira test tests` to find out whether the change
still works.

## The harness next door

`/root/Dev/kira-projects/kira/tests-kik/harness` is a second suite: a copy of
the original Kira harness, kept so the reimplementation is checked against the
one it replaces rather than against itself. It is a separate repository and
its own test count moves independently of this one.

`corpus/` is the third: `.klfd` files whose `@Test` functions run inside the
language definition itself, so a change to the checker is measured by the
checker.

```sh
cd <repository root>
klf test languages/kira
```
