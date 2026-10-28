# Foundation: concurrency

Threads, deferred tasks and the executor, channels, and atomic operations with their memory ordering.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `class Executor`
- `class ExecutorJoin`
- `class ExecutorTask`
- `enum ChannelFailure`
- `enum DeferredTaskStatus`
- `enum MemoryOrder`
- `enum Poll`
- `struct Async`
- `struct ChannelState`
- `struct Context`
- `struct DeferredTaskState`
- `struct JoinHandle`
- `struct MainThreadTask`
- `struct ReadyFuture`
- `struct Receiver`
- `struct Sender`
- `struct Task`
- `struct Thread`
- `struct ThreadBody`
- `struct ThreadId`
- `struct Waker`
- `struct YieldFuture`
- `trait Future`

## Files

- Atomic.kira
- Channel.kira
- Executor.kira
- Future.kira
- Task.kira
- Thread.kira
