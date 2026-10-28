# Logging categories

Status: normative. Each section says whether it is **implemented** (in the
parser or `std/Foundation`, and covered by a corpus case) or **planned**.
Read with `subset.md` (the `log` entries) and `diagnostics.md` (2094-2105).

Purpose: a program turns on the diagnostics it needs at runtime, by category,
without a probe, a `print`, or a rebuild. Libraries declare their own
categories; the program declares its own.

## 1. Categories (implemented)

A category is a case of an enum that conforms to Foundation's `LogCategory`
trait.

```kira
enum Tls: LogCategory {
    Handshake
    Records
    Alerts

    function threshold(borrow self) -> TrailThreshold {
        match self {
            Handshake -> return .UpTo(.Info)
            Records -> return .Off
            Alerts -> return .UpTo(.Warn)
        }
    }
}
```

- `threshold` is the category's **declared default**: the quietest level it
  prints until a rule says otherwise. `Off` prints nothing until something
  enables it. It is a `match`, so every case states its default.
- **Identity** is module, enum and case. The stable path is
  `<module>.<Enum>.<Case>`, for example `Network.Tls.Handshake`, where the module
  is the package's name. Configuration names paths.
- Categories may be declared in any file of a package. A library's `public`
  enum is a category set other packages may log to and configure.

### The implicit category

A `log` with no `category:` argument writes to the module's implicit category,
whose path is the module name alone (`Network`). Every existing `log` call is
this form and keeps its meaning. Rules on the module name therefore cover it:
`Network=debug` is the old `KIRA_LOG` form.

### Logging to a category

```kira
log(category: Tls.Handshake, "peer accepted", peer)
log trace(category: Tls.Records, "record", length: bytes.count)
log warn(category: Tls.Alerts, "alert received", code)
```

- The argument is the labelled `category:`, written `Enum.Case`. The
  leading-dot form `.Handshake` is not used: at the log site there is no
  expected type to resolve it against.
- `category:` is reserved in `log` argument lists, and given at most once. A
  value not written `Name.Name` is error **2105**. A value that is written so but
  names no `LogCategory` enum or case is an ordinary type error at the log site:
  there is no separate code for it.
- `fault` and `warn` still need a leading message (2095).
- The level and the category are independent: `trace` in `Records` prints only
  when `Records` is enabled at `trace`.

Mechanics (for the parser's owners): the parser removes the `category:` argument
and emits `trailCategorySite(…, categoryPath, value)` in place of `trailSite`.
The loader fills `categoryPath` as the module's trail followed by the written
name. `trailOpen(level, site)` takes the site number, so an undescribed site is
always let through to describe itself.

## 2. Levels and the decision (implemented)

Levels are `fault`, `warn`, `info`, `debug`, `trace`. A threshold is `Off` or
`UpTo(level)`.

An event at level `L` in category `C` prints iff `effective(C).admits(L)`. An
event is **recorded** in the ring iff `L` is `debug` or louder (`fault`,
`error`, `warn`, `info`, `debug`), whatever its threshold; the ring is the crash
history. A `trace` event is recorded only when it prints. So a category set to
`Off` still records its `info` and louder events, and their fields are evaluated
for them; a `trace` event in an `Off` category evaluates nothing.

An implicit-category event with no configuration prints at `info` and up
(`TrailDefault.program`, `TrailDefault.library`).

## 3. Configuration and precedence (implemented)

Three sources, lowest to highest precedence:

1. **Declared default**: the `threshold` the category's enum returns (or the
   program/library default for the implicit category).
2. **Environment**: `KIRA_LOG`, read once, when the trail is first used.
3. **API**: `Log.enable`, `Log.disable`, `Log.set`, `Log.reset`, at any time. A
   later call replaces an earlier rule for the same path, so the API wins over
   `KIRA_LOG`.

A bare `KIRA_LOG` threshold (`warn`) is the general threshold: it replaces the
declared default of every category that no rule names. That is the old meaning.

### Rules and paths

A rule names a path. It applies to the category at that path and to every path
inside it (dot-bounded). The longest matching rule wins; with equal length, the
later one set wins.

| Form | Matches | Status |
| --- | --- | --- |
| `Shop.net=trace` | `Shop.net`, `Shop.net.Tls.Handshake`; not `Shop.network` | implemented |
| `Network.Tls.Handshake=trace` | exactly that category | implemented |
| `Network.Tls.*=debug` | every category inside `Network.Tls` | implemented (a family is the rule for its prefix) |
| `warn`, `off` (bare) | the general threshold | implemented |

`KIRA_LOG` items that name no threshold, or have an empty prefix, are ignored.

### `Log` (implemented)

```kira
let Log: LogControl = LogControl {}

struct LogControl {
    function enable(borrow self, path: String, level: TrailLevel) -> Result<Void, LogConfigFailure>
    function disable(borrow self, path: String) -> Result<Void, LogConfigFailure>
    function set(borrow self, path: String, threshold: TrailThreshold) -> Result<Void, LogConfigFailure>
    function reset(borrow self, path: String) -> Result<Void, LogConfigFailure>
    function categories(borrow self) -> [LogCategoryInfo]
}

enum LogConfigFailure {
    MalformedPath(String)
}

struct LogCategoryInfo {
    let path: String
    let threshold: TrailThreshold
    let declared: TrailThreshold
}
```

- The paths are the strings `KIRA_LOG` uses: `"Network.Tls.Handshake"`,
  `"Network.Tls.*"`. The API takes the path as text and not the category value,
  because a `LogCategory` value carries no path at run time. A typed form
  (`Log.enable(Tls.Handshake, …)`) would need the compiler to pass the path with
  the value; that is **planned**.
- A malformed path (an empty segment, `*` anywhere but the last segment) is
  `MalformedPath`. A well-formed path naming a category not yet run is accepted
  and applies when the category first runs.
- `categories()` lists every category that has described itself (has run at
  least once), once each, with its current threshold and declared default. It
  is not sorted.

## 4. Registry (implemented, with one gap)

- A category **registers** the first time one of its events runs. Configuration
  is stored by path, so it applies before the category exists.
- **Gap, planned:** `categories()` does not list a declared category that has
  not run yet. Listing those needs a compile-time collector of every
  `LogCategory` enum in the program, like the `TestRunner` collector.

## 5. Cost (implemented)

- An event whose level is admitted by the loudest threshold in use costs one
  atomic load and a compare, then the site's cached threshold check.
- The loudest threshold is kept in the shared block; configuration changes
  rewrite it and bump a generation. A site re-reads its threshold once per
  generation.
- An event that is **not** admitted by the loudest threshold takes the trail's
  lock to look up its site. That is the current cost of a disabled event whose
  category is off. **Planned:** a lock-free site table, so disabled events cost
  only the atomic load.
- Field expressions are evaluated only when the event records (`trailBegin`
  returns false otherwise).
- **Compile-time removal of `trace`/`debug`** in release builds is **not
  implemented**. It needs the semantic phase to fold `Build.release()` in a `log`
  expansion. Planned.

## 6. Thread safety (implemented)

- Every change to the trail's state, and every write to standard output, is
  made under one reentrant lock. The lock is a word the atomic operations
  compare-and-swap, with the owner thread and a depth kept beside it. A thread
  that holds the lock may take it again, which a field's expression that logs
  needs.
- The lock is held for one step at a time. An event's fields are evaluated
  outside it, so a field that waits on another thread cannot deadlock the trail.
- Open events are kept on one stack of `(thread, site, values)`. `trailField`
  and `trailEnd` take the innermost event of the calling thread, so two threads'
  events never mix, and a nested event inside a field finishes before its outer
  one continues.
- The trail's block is allocated when the trail state is first built. The first
  construction is not itself locked: the first use of the trail must not race
  another thread. In practice that is the program's first `log`, or the start of
  `main`.

## 7. Output (implemented, format unchanged)

- The stream is standard output, as before. The rendered format is kept:
  `level[trail]: message`, the ` --> file:line:col` line, the snippet with
  carets, then `= name: value` per field.
- A categorised event renders as an implicit one: its header shows the module's
  trail. The category's path is not yet shown. **Planned,** with a BootLog update
  in the same change.
- **Consumers**: `tessera/build/app/BootLog.kira` and the boot scripts parse this
  format. Nothing here changes it.
- **Planned:** timestamps and category in the header; a `TrailSink` interface
  for file and serial output (stdout stays the default); structured output.

## 8. Migration and rules for committed code

- Existing `log` calls keep working unchanged (implicit category).
- No probe, smoke-test code, or temporary `print` may be committed. Use a
  category, and enable it with `KIRA_LOG` or `Log.enable` when debugging. A
  `print` is only for a command's own output to its user (`idiomatic-kira.md`).
- Framework `print`-based debug leftovers move to a category when trivial; this
  change converts none (none were in the framework's Foundation files).

## 9. Open items

1. Typed `Log.enable(Enum.Case, …)` (needs the path passed with the value).
2. Listing declared-but-unused categories (comptime collector).
3. Lock-free disabled path (section 5).
4. Compile-time removal of `trace`/`debug` in release builds.
5. Header shows the category; BootLog update in the same change.
6. Sinks (file, serial) and structured output.
7. Out-of-process reconfiguration: a control file re-read by a thread, a signal
   that sets a flag the program polls, or a Foundation service. Each ends in
   `Log.set`; none needs another rule.
