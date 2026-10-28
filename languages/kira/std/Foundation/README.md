# Foundation

The standard library every Kira program may import by name. Source lives in `app/`, one module, grouped by domain. The wire format, macro and compile-time rules are in `languages/kira/docs/subset.md`.

| Domain | Purpose |
| --- | --- |
| `app/core` | language core: optionals, results, tuples, closures, runtime values, ambient state |
| `app/collections` | `Array` helpers, `Map`, `Set` |
| `app/memory` | raw byte allocation over Heap |
| `app/text` | `String`, Unicode, C strings |
| `app/numerics` | `Number`, `Math`, `Geometry` |
| `app/time` | monotonic clock, UTC dates |
| `app/io` | files, directories, bundled assets |
| `app/process` | child processes, environment, exit helpers |
| `app/concurrency` | threads, tasks, executor, channels, atomics |
| `app/encoding` | byte readers and writers, wire format |
| `app/formats` | JSON, DEFLATE, PNG, JPEG, klist, Ksl |
| `app/diagnostics` | error catalogue, trace, trail |
| `app/testing` | `@Test`, `expect`, test runner |
| `app/derive` | `@Derive` macros and serde helpers |
| `app/syntax` | `Syntax` values and edit helpers |
| `app/net` | networking, crypto, `quic/`, `tls/` |

Heap is a separate package (`std/Heap`), a dependency of Foundation.
