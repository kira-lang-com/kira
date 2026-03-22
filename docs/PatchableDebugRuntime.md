# Kira Patchable Debug Runtime

## Architecture Summary

Kira's Phase 1 debug runtime is a distributed, debug-only patch system built around one rule:

- restart the Kira app layer
- keep the native host process alive

The system is split into four layers:

1. Patch compiler
   - `Sources/KiraCompiler/HotReload/PatchCompiler.swift`
   - Rebuilds Kira bytecode, computes function/type/module digests, and emits a signed patch bundle.
2. Patch server
   - `Sources/KiraCompiler/HotReload/PatchServer.swift`
   - Listens on TCP, advertises `_kira-debug._tcp`, authenticates clients, tracks generation, and broadcasts bundles.
3. Embedded debug runtime client
   - `Sources/KiraVM/EmbeddedPatchClient.swift`
   - Discovers or connects, performs the handshake, validates patches, and reports apply results.
4. Host bridge
   - `Sources/KiraVM/DebugHostBridge.swift`
   - Owns Kira runtime boot/reload/dispose and applies patches only at safe points.

## Core Components

- Shared protocol and compatibility model:
  - `Sources/KiraDebugRuntime/DebugRuntimeProtocol.swift`
  - `Sources/KiraDebugRuntime/DebugRuntimeHashing.swift`
- Compiler-side bundle creation:
  - `Sources/KiraCompiler/HotReload/PatchCompiler.swift`
- Server lifecycle and delivery:
  - `Sources/KiraCompiler/HotReload/PatchServer.swift`
- Embedded host bridge and controller:
  - `Sources/KiraVM/DebugHostBridge.swift`
  - `Sources/KiraVM/EmbeddedPatchClient.swift`
- Native bootstrap wiring:
  - `Platform/macOS/AppDelegate.swift.template`
  - `Platform/iOS/AppDelegate.swift.template`
- CLI entry points:
  - `Sources/KiraCLI/Commands/RunCommand.swift`
  - `Sources/KiraCLI/Commands/WatchCommand.swift`

## Runtime Data Model

The shared wire model lives in `KiraDebugRuntime`.

- `KiraPatchManifest`
  - session ID
  - generation
  - target app identifier
  - project name
  - runtime ABI version
  - bytecode format version
  - host bridge ABI version
  - changed modules
  - dependency closure
  - per-module digests
  - metadata hash
  - integrity hash
  - session signature
- `KiraPatchBundle`
  - manifest
  - bytecode
  - optional source map
  - debug metadata
  - optional asset deltas
- `KiraRuntimeCompatibilitySnapshot`
  - exported function digests
  - public type digests
  - bridge-visible symbol set
  - per-module implementation hashes

## Handshake Protocol

The client/server handshake is explicit and authenticated.

1. Client connects directly by host/port or via Bonjour discovery.
2. Client sends `KiraDebugHandshakeHello`:
   - wire version
   - session ID
   - target app identifier
   - project name
   - client name
   - platform name
   - runtime ABI version
   - bytecode format version
   - host bridge ABI version
   - current generation
   - session token
3. Server validates:
   - wire version
   - session ID
   - session token
4. Server replies with `KiraDebugHandshakeAck`.
5. Server streams:
   - `patch` messages with full bundles
   - `status` messages for compile/apply failures

Wire transport is newline-delimited JSON in Phase 1.

## Patch Bundle Structure

Patch bundles are self-describing and signed.

- Manifest includes ABI/version targets and compatibility metadata.
- `metadataHash` hashes structural digests.
- `integrityHash` hashes `metadataHash + bytecode`.
- `sessionSignature` hashes `sessionID + token + integrityHash + generation`.

Clients reject patches that fail integrity or session validation.

## Client Reload Lifecycle

`KiraBytecodeHostBridge` implements the patchable Kira lifecycle:

1. `boot(runtimeConfig)`
   - load bundled bytecode
   - restore compatibility snapshot from bundled manifest when present
   - run `__kira_init_globals` if present
   - run entry function
2. `reloadApp(patchBundle)`
   - queue the patch
   - apply only when no callback is executing
3. `disposeApp()`
   - drop the active VM and Kira runtime state

On apply:

1. validate bundle
2. compute compatibility level
3. stop at a safe point
4. tear down the old VM
5. load new bytecode
6. rerun `__kira_init_globals`
7. rerun the entry function
8. keep the native host shell, process, and surface alive

## Compatibility Checking

Compatibility is explicit and strict.

- `hotPatch`
  - exported function digests unchanged
  - public type digests unchanged
  - bridge-visible symbols unchanged
  - implementation hashes changed
- `softReboot`
  - exported signatures changed, or
  - public type layouts/conformances changed, or
  - bridge-visible symbol set changed
- `fullRelaunchRequired`
  - target app identifier changed, or
  - runtime ABI changed, or
  - bytecode format changed, or
  - host bridge ABI changed

Phase 1 always rebuilds the Kira VM/app layer for accepted patches. It never hot-patches arbitrary native code.

## Safe-Point Model

Patches are never applied mid-instruction.

Phase 1 safe points are host callback boundaries:

- before callback dispatch
- after callback dispatch
- end of frame

`KiraBytecodeHostBridge` serializes callback execution and patch application on one queue. Incoming patches wait until the current callback drains.

## Host Bridge API

The host bridge contract is intentionally narrow:

- `boot(runtimeConfig:)`
- `attach(surface:)`
- `loadInitialApp(entryModule:)`
- `reloadApp(patchBundle:)`
- `disposeApp()`
- `currentGeneration()`
- `debugStatus()`
- `compatibilitySnapshot()`
- `runCallback(named:args:)`

The native host does not need to understand bytecode patch internals.

## Initial Implementation Plan

Phase 1 is implemented now:

- one patch server
- one embedded client per app instance
- TCP transport over `Network.framework`
- Bonjour advertisement on supported platforms
- strict authentication and integrity checks
- full Kira app restart inside the host process
- no automatic durable Kira state preservation

Future phases can add:

- multi-client fanout improvements
- richer safe points and scheduler barriers
- snapshot/restore of opt-in durable Kira state
- asset patching and rollback
- stricter localhost-only bind behavior

## Phase 2 Additions

Phase 2 now includes two concrete upgrades on top of the Phase 1 baseline:

1. Opt-in reload-stable state restore
   - Native host config can keep the default hook names:
     - `__kira_debug_snapshot_state`
     - `__kira_debug_restore_state`
   - Before replacing the old Kira VM, the host bridge calls the snapshot hook if present.
   - The snapshot must return `String` or `nil`.
   - After the new Kira VM is mounted, the bridge calls the restore hook with that snapshot string if present.
   - This is intentionally explicit and narrow; Phase 2 still does not auto-serialize arbitrary runtime state.

2. Patch history and catch-up
   - The patch server now keeps a bounded in-memory history of recent patch bundles.
   - When a client handshakes with an older generation, the server immediately sends the newest compatible bundle it has.
   - This lets a native host that attaches late catch up to the current generation without waiting for the next file save.

## Risks and Edge Cases

- Localhost-only mode currently suppresses discovery intent, but listener binding is still Phase 1 coarse-grained.
- The macOS native debug path rebuilds the staged app sources before generating patches, which is correct but heavier than a true incremental module pipeline.
- Newly added source files are detected through watched source roots, not OS-native recursive file watching.
- Long-running host callbacks defer patch application until the callback returns.
