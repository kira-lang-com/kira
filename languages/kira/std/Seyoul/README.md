# Seyoul

Async I/O, timers and tasks for Kira, written in pure Kira over Foundation's
futures (`Future`, `Poll`, `Waker`, `Async`) and the kernel's `klf.net`
poller. What Tokio is to Rust.

```kira
import Foundation
import Seyoul

async function echo(incoming: Incoming) -> Number {
    match incoming.connection.read(4096).await {
        Ok(bytes) -> {
            let sent = incoming.connection.writeAll(copy bytes).await
            let closed = incoming.connection.close()
            return bytes.count
        }
        Error(failure) -> return 0
    }
}

async function serve(listener: Listener) -> Number {
    var served: Number = 0
    while true {
        match listener.accept().await {
            Ok(incoming) -> {
                let task = spawn(echo(move incoming))
                served += 1
            }
            Error(failure) -> return served
        }
    }
    return served
}

@Main
function main() {
    match listen("127.0.0.1:7000") {
        Ok(listener) -> {
            let served = run(serve(move listener))
        }
        Error(failure) -> print("cannot listen")
    }
}
```

## What there is

| | |
|---|---|
| `run(future)` | drives a future and every task it spawns until it finishes |
| `spawn(future)` | a task beside the caller; await its `JoinHandle`, or `abort()` it |
| `sleep(seconds)`, `sleepUntil(instant)` | ready once the time has passed; `now()`, `Instant` |
| `timeout(seconds, future)` | the output, or `.None` when the time ran out first |
| `select(first, second)` | `.First` or `.Second` with the output of whichever finishes first; the other is cancelled |
| `listen(address)`, `listener.accept()` | TCP listener; `Incoming { connection, peer }` |
| `connect(address)` | a TCP `Connection`: `read(capacity)`, `writeAll(bytes)`, `shutdown()`, `close()` |
| `bind(address)` | a `UdpPort`: `send(bytes, peer)`, `receive(capacity)` |
| `Mailbox<Value>()` | many senders, one receiver, on one thread: `send(value)`, `receive()`, `close()` |
| `boundedMailbox<Value>(limit)` | a mailbox holding at most `limit`: `send` refuses when full, `deliver(value)` waits for room |
| `Conduit<Value>()` | a mailbox between threads |
| `workerPool(threads)` | threads each running a runtime of their own: `spawn(future)`, `join()` |
| `runAll(future)` | `run`, until every spawned task has finished too |

## How it runs

- **Tasks** are Foundation `Executor` slots: a dense array of task states and
  a ring of woken indices. A wake writes one word; a run walks two flat arrays
  and the futures themselves. An `async function`'s future is one heap frame
  holding its locals and the future it waits on, so polling a chain of awaits
  touches memory the chain owns and nothing else.
- **The reactor** watches each socket once, for both directions, when it is
  made. The poller reports readiness when it changes, so every operation tries
  the socket first and leaves its waker only on `WouldBlock`; a socket with
  data ready answers without a turn. A turn waits into one event buffer
  allocated with the reactor, so nothing is allocated per turn. Per-socket
  state is three parallel arrays indexed by token.
- **Timers** are a binary min-heap over three parallel arrays of words.
  Cancelling bumps the timer slot's stamp instead of digging the entry out;
  stale entries are skipped when they reach the top. Slots are reused.
- **Threads share nothing.** Each thread has a runtime of its own
  (`@ThreadLocal let seyoul`), so a task, its sockets and its timers stay on
  the thread that started them, and nothing touched per poll is shared. A
  `WorkerPool` hands each spawned task to the next worker in turn. Threads
  exchange values through a `Conduit`, a ring under a spin lock held for one
  push or take; a send that finds the receiver waiting leaves its waker in
  the receiver runtime's inbox and wakes that runtime's poller, so a run
  queue is only ever touched by its own thread.
- **A turn** runs once the run queue is empty: it fires due timers, and
  otherwise blocks on the poller until a socket is ready or the next timer is
  due. When nothing is armed and nothing waits on a socket, no wake can ever
  come, and `run` traps instead of hanging.

## Not yet

- Work stealing between a pool's workers; today a task stays on the worker
  it was handed to.
- A pool on the VM, whose one thread runs a spawned thread's body inline.
- Sockets closed on drop; today `close()` is explicit.
- `select` over several futures, and bounded mailboxes.
