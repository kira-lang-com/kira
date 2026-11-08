# Foundation: process

Child processes, environment and current directory, and the process exit, abort and assert helpers.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum ChildExit`
- `enum ChildOutput`
- `enum ChildRead`
- `enum ChildStream`
- `enum ProcessFailure`
- `enum ProcessSignal`
- `enum PluginFailure`
- `enum PluginExit`
- `struct ChildProcess`
- `struct PluginHandle`
- `distinct PluginResourceId`
- `struct CommandResult`
- `struct EnvironmentEntry`
- `struct ProcessCommand`

## Files

- ChildProcesses.kira
- Environment.kira
- Process.kira
- Plugins.kira

## Installed plugins

`Plugin.start(installedId)` starts an installed Kira app by catalog ID. It
returns a `PluginHandle` with `poll`, `wait`, and `stop`, not a command builder.
Host RIDL services and a private channel are provided by the Kira runtime.

`plugin.shareFile(file, PluginResourceId(7))` transfers a clone of an existing
Foundation `FileHandle` to that plugin. The host retains its own file and its
access rights are not widened. Only the receiving plugin gets the transferred
resource.

The runtime embedder must configure the catalog and host RIDL exports before
calling `Plugin.start`. Native/hybrid plugin OS sandboxing is not yet present.
