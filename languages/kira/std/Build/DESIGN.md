# Kira Build: design

Status: design of record, 2026-10-15. It covers how any Kira project describes
and runs its build: compiling Kira packages, assembling SDKs and file trees,
packing archives and disk images, fetching and patching upstream sources, and
driving the external builds a project cannot avoid (a Linux kernel, Mesa). A
capability this document does not name is out of scope until it is added here
first.

The library is generic. Nothing in it knows about a particular project: an
operating system's components, install paths and images are that project's own
build package, written against this library.

## 1. Goals

1. **The build is a Kira program.** A project's build is a Kira package, typed
   and checked like any other. Configuration is values, decisions are `match`,
   and shared logic is functions. There is no second language, no shell and no
   string templating.
2. **A graph, not a script.** The program declares artifacts and the actions
   that produce them. The library decides what runs, in what order and in
   parallel. Nothing runs that no requested step needs.
3. **Correct by content.** Every action is keyed by the digest of everything it
   reads: its description, its tool and its inputs. An unchanged key never runs
   again. An output that comes out byte-identical stops its dependents from
   running (early cutoff), so a library whose `.ridl` contract did not change
   rebuilds none of its dependents without any code saying so.
4. **Explainable.** `-explain <step>` names, for each action that runs, the
   input that changed since its last run. `-graph` prints the graph.
   `-dry-run` lists what would run.
5. **Kira all the way down.** Archives, compressors, disk image writers,
   downloads, patching and signing are Kira code in bundled libraries. An
   external program runs only for a build Kira does not own: an upstream
   project's own build system (kbuild, meson) and an emulator.
6. **Toolchains through knvm.** The Kira compiler a build uses is the one knvm
   selects for the project directory, pins included. The toolchain's tree is an
   input of every action that runs it.

Non-goals for this period: remote caching and remote execution (the cache
layout in section 6 allows both later), filesystem sandboxing of actions, and
watching files.

## 2. Layers

```
 a project's build/ package
 ──────────────────────────────────────────────────────────────── Build (Kira)
  Graph · Artifact · Step · Option                                  description
  Kira rules: program, library (binary + contract), test, SDK       rules
  Tree, copy, write, download, extract, patch, strip, sign, pack    actions
  Scheduler · action cache · content store · explain · report       engine
 ──────────────────────────────────────────────────────── Archive, Elf (Kira)
  Tar · Ar · Cpio · Squashfs · Composefs · Deflate/Gzip · Zstd · Xz formats
  ELF: strip, debug information, interface stub, machine            binaries
 ──────────────────────────────────────────────────────────────── Network, Kten
 ──────────────────────────────────────────────────────────────── Foundation
  ProcessCommand, ChildProcess, FileStatus, links, modes, file digests
 ──────────────────────────────────────────────────────────────── KLF kernel
  klf.process (spawn, wait, pipes)   klf.fs (status, modes, links)   klf.crypto
```

`Build`, `Archive` and `Elf` are bundled libraries under `std/`, beside `Network` and
`Kten`, imported by name like `Network`; the sysroot unit does not compile them. `Archive`
and `Elf` stand on their own: a program that unpacks a `.tar.xz` or strips a
binary needs no build system.

## 3. What the kernel provides

Foundation's wrappers are the only callers.

### 3.1 `klf.process`

A child is a handle. It is built argument by argument, started, and waited for
by any thread.

| Service | Meaning |
| --- | --- |
| `spawn_create() -> handle` | an empty command |
| `spawn_argument(h, text)` | appends an argument; the first is the program |
| `spawn_environment(h, text)` | sets one `NAME=value` |
| `spawn_clear_environment(h)` | starts from an empty environment |
| `spawn_directory(h, path)` | the working directory |
| `spawn_stream(h, stream, mode, path)` | stream 0, 1 or 2: inherit, null, pipe, or a file (read for 0, truncated for 1 and 2) |
| `spawn_start(h) -> child` | starts it; the command handle is released |
| `child_wait(child, timeout) -> state` | running, exited with a status, or ended by a signal |
| `child_wait_any(timeout) -> child` | the first started child that ended, or none |
| `child_read(child, stream, buffer) -> count` | bytes from a piped stream; 0 at its end; would-block is its own answer |
| `child_write(child, buffer) -> count`, `child_close_input(child)` | the piped input |
| `child_signal(child, signal)` | interrupt, terminate or kill |
| `child_release(child)` | forgets an ended child |
| `current_directory(buffer)` | the process's working directory |

The serial `command_push`/`command_run` services stay for definitions, which
are not Kira programs.

### 3.2 `klf.fs`

| Service | Meaning |
| --- | --- |
| `status(path, follow) -> record` | kind (file, directory, link, other), size, permission bits, modification time in nanoseconds, device and inode |
| `set_mode(path, bits)` | permission bits |
| `symbolic_link(target, path)`, `read_link(path)` | links |
| `hard_link(from, to)` | a second name |
| `copy(from, to)` | a copy that keeps permission bits, cloned where the filesystem can |
| `set_length(path, length)` | a sparse file of that length |

### 3.3 `klf.crypto`

`digest_file(algorithm, path)` hashes a file in the kernel without moving its
bytes through Kira. The content store hashes every input this way.

### 3.4 `klf.net`

`unix_connect(path)` opens a Unix stream socket, so a build can talk to a
running emulator's monitor. It joins the TCP handles of `klf.net`.

## 4. The build package

A project with a build has a `build/` directory beside its `package.kira`: an
app package whose `main` hands its graph to the library.

```
project/
  package.kira          the project itself, when it is one package
  build/
    package.kira        construct ProjectBuild extends Package, depends on Build
    app/*.kira          the graph
  .kira-build/          what the build writes (section 6), never committed
```

```kira
import Foundation
import Build

@Main function main() -> Number {
    var graph = buildGraph("Shop")
    let target = graph.option(Choice {
        name: "target",
        summary: "the triple to build for",
        values: ["x86_64-linux", "aarch64-linux"],
        fallback: "x86_64-linux"
    })
    let kira = graph.kira()
    let server = kira.program(graph, KiraPackage { path: "server", target: target })
    graph.step(Step {
        name: "server",
        summary: "the server binary",
        produces: [server]
    })
    return graph.run()
}
```

`buildGraph` reads the command line, so `graph.option` answers what it gave.
`graph.run()` resolves the requested steps, runs what they need and returns the
exit status: 0 when everything succeeded, 1 when something failed, 2 when the
command line or the graph is wrong and nothing ran. A build program does
nothing else with its command line.

## 5. The model

### 5.1 Artifacts

An `Artifact` is a distinct id naming a file or a tree that exists once the
graph runs. It has no path at description time. An action receives the paths
of its inputs and outputs when it runs.

- `graph.source(path)` is a file of the project, by its path from the project
  root.
- `graph.sourceTree(path, excluding: [...])` is a directory of the project. Its
  digest covers every file name, permission bit and byte under it.
- Every other artifact is an output of exactly one action.

### 5.2 Actions

```kira
enum Action {
    Run(CommandAction)
    Native(NativeAction)
}
```

- A `CommandAction` runs an external program. Its arguments are
  `Argument.Text`, `Argument.Input(artifact)` and `Argument.Output(name)`, so
  every path in the command line is one the library placed. It declares its
  environment; the child starts from an empty one. The variables it names in
  `inherited` it is given from the build's own environment as they are when
  it runs, and its key leaves them out: a search path such as `PATH` differs
  from shell to shell while the programs it finds, which are keyed by their
  own digests, do not. It runs in a fresh working
  directory under `.kira-build/work/`, named by the action's label and
  outputs rather than its key, so a run over edited inputs finds them at the
  paths the last run had them; a compiler that caches by what it read
  (KLF-RIDL section 8.9) then answers for what did not change. Its `tool` is resolved on `PATH` once,
  and the tool's own file is an input.
- A `NativeAction` is a Kira function the build process runs itself, with
  `parameters` (Kten) and its `code` as part of its key. `code` is
  `sourceDigest!()` written in the package the function is in: the SHA-256 of
  that package's sources and of every package it imports, which the compiler
  writes in. An edit to that code, or to a library it calls, changes the key;
  nobody bumps a version by hand, and an edit elsewhere keeps it. The
  library's own actions, and a project's that should not run again for a new
  toolchain, write `sourceDigest!("package")`, the digest of the package's
  own sources alone: a new Foundation, Archive or toolchain leaves their keys
  as they were, and an edit to Build itself changes them. Every
  packer, downloader and tree operation of the library is one. An action that
  names the SHA-256 of the one file it makes, from no inputs, in `produces` is
  keyed by that digest and the file's name alone: its code and parameters are
  left out, so a download is not fetched again because the library changed or
  the file moved to another URL. The file having another digest fails it.

A command's inputs are placed in its working directory as copies of their own,
cloned where the filesystem can: a program running as root writes through
read-only bits, and the store must not change under it. A native action's
inputs are second names of the stored files, since the library's own Kira code
does not write them; it reads a tree's permission bits from `NativeRun.trees`.
An input lands under `inputs/<n>/` unless the command places it at a path of
its own with a `PlacedInput`; then it is at that path only, and an argument
naming it reads that path.

A command may also:

- read sources where they are, listed in `reads`: never placed, an argument
  naming one is its absolute path, and its key holds that path with the
  source's digest. Only a source can be read in place; the Kira rules read
  the package and the toolchain so.
- name a `depfile`, a path in its working directory outside `inputs/`,
  `outputs/` and `scratch/`, where it writes a make-style depfile of what
  else it read (section 5.3).
- send its standard output to one of its file outputs, `standardOutput`,
  instead of the logs; a failure report shows that output's last lines too.
- set `variables`, environment variables whose value is an `Argument`, so one
  can hold a placed input's path.
- name a `workspace`, a directory kept from run to run at
  `.kira-build/workspaces/<name>/`, which `Argument.Workspace` names. A tool
  that redoes only what changed, as make, kbuild and cargo do, keeps its
  objects there. Keys are unchanged: the command still runs only when its key
  misses, and what it reads in its workspace is no discovered input. One
  command at a time runs in a workspace.
- run in a `directory` of its own, an `Argument`, such as a source tree in
  its workspace, instead of its working directory.
- run more programs after its tool, `followedBy`: `CommandStage`s, each with
  its tool, arguments and directory, started in order once the one before
  exited with 0, with the command's environment. Configuring, building and
  installing a project is one action so, with no shell between them. Their
  tools and arguments are in the key; the logs hold the last stage's output,
  so a failure report shows the program that failed.

Each action declares its outputs by name. An output missing when the action
ends fails it. A declared input is the only path an action is handed; an
action that reads something else is a bug in its rule, and the rules in this
library read nothing else.

### 5.3 Discovered inputs

The Kira compiler reads files no rule can list before it runs: the sources of
path dependencies, contracts from an SDK, embedded `klist!` and `ksl!` files.
`kira build --depfile <path>` writes every path the compile read, asked the
existence of or listed (KLF-RIDL section 5.5). The library keys a command
with a depfile in two levels:

1. The declared key: the action with its inputs, which for a compile are the
   toolchain and the package tree.
2. The record under that key lists the discovered paths and their digests. A
   path relative to the working directory is the command's own; one under the
   working directory or under a source the command reads in place is covered
   by the key and is not listed. A file's digest is its SHA-256, a
   directory's is the SHA-256 of every name under it (a directory's ending in
   `/`, in byte order), and a path that is not there is `absent`. The record
   is a hit only when every listed path still has its digest.

So the first build of a package runs, and later builds rebuild exactly when a
path the compiler read changed: a file edited, a file added to or removed
from a directory it listed, a missing path that appeared. `-explain` names
the paths that changed.

### 5.4 Steps and options

A `Step` is a name the command line can ask for, with the artifacts it
produces. `kira build <step>` materializes them under `.kira-build/out/<step>/`.
A step may also run something once its artifacts exist (`Step.run`), such as
booting an image; that part is never cached. It is given each artifact's path
(`StepRun.paths`) and the digest the store keeps it under (`StepRun.digests`),
so it never hashes an artifact again. A step whose artifacts are the ones
already placed, with nothing under its directory changed, added or removed
since, keeps them where they are.

An `Option` is a `-name value` the command line may give, declared with its
values and its fallback. The build program turns the text into its own enum
once, where it reads it.

### 5.5 Kira rules

`graph.kira()` resolves the compiler as the knvm launcher does for the
project's root: the nearest `kira-toolchain.toml` at or above it, else the
selection in `toolchains/kira/current.toml`, both under `$KLFD_HOME` or
`~/.klf`. A toolchain not installed is a problem of the graph. Its identity in
keys is the digest of the toolchain tree: driver, definitions, standard
library and bundled libraries.

```kira
let kira = graph.kira()
let shop = kira.program(graph, "apps/shop", KiraSettings { release: true })
let greet = kira.library(graph, "libs/greet", KiraSettings {})
let sdk = graph.sdk("sdk", [KiraFramework { module: "Greet", library: greet }])
```

| Rule | Produces |
| --- | --- |
| `kira.program(graph, package, settings)` | an executable |
| `kira.library(graph, package, settings)` | a `KiraLibrary`: a shared binary and its `.ridl` contract |
| `kira.tests(graph, package, settings)` | what the test run printed; a failing test fails it |
| `graph.sdk(name, frameworks)` | an SDK tree (KLF-RIDL section 27.7) |

`package` is a directory from the project root holding `package.kira`.
`KiraSettings` holds the target triple, `release`, `optimize` (the KIR
optimizer, `--optimize`), the SDK, the sysroot and the paths under the package
its key leaves out. Each compile runs the
toolchain's own driver, reads the package and the toolchain in place, writes
a depfile, and passes the build's `HOME`, `PATH`, `KLF_HOME`, `KLF_CACHE` and
`KLFD_HOME` on. A source SDK or sysroot is read in place, a produced one
placed; the sysroot is `KLF_SYSROOT`. A contract is its own artifact, so a
dependent that builds against an SDK keys on contracts, never on library
binaries. An SDK places each framework's binary at
`System/Library/<Frameworks or PrivateFrameworks>/<Module>.framework/<Module>`
and its contract at `Resources/<Module>.ridl` beside it.

### 5.6 Library actions

Each is a native action whose first argument, `name`, is what its output is
called and what its label reads. A path in a tree is `/`-separated from the
tree's root, without a leading `/`, `.` or `..`.

| Function | What it does |
| --- | --- |
| `write(name, text, mode)`, `writeBytes(name, bytes, mode)` | a file from the build program's own values |
| `copied(name, artifact, mode)` | a file under a new mode (`copy` is a keyword) |
| `tree(name, parts)` | a tree of `TreePart`s: `Place` puts a file, under its own mode or one given, or a whole tree, at a path; `Directory` and `Link` add those. A directory above an entry that no part names gets 755. Two parts at one path fail it, but directories with the same bits |
| `union(name, trees)` | one tree from several; a directory several hold is one when its bits agree, and any other path two trees hold fails it, naming both |
| `subtree(name, tree, path)` | the part of a tree under a path |
| `member(name, tree, path)` | the file at a path in a tree, under its own mode |
| `strip(name, binary)` | a `StrippedBinary`: `binary`, the ELF executable or shared library without its debug information, as `llvm-strip --strip-unneeded` leaves it, and `debug`, that information alone, as `llvm-objcopy --only-keep-debug` takes it (section 8) |
| `interfaceStub(name, binary)` | the interface stub of an ELF shared library, as `llvm-ifs --output-elf` writes it: its dynamic symbols, needed libraries and soname alone, for linking against without relinking when only its code changes (section 8) |
| `download(name, url, sha256)` | a file fetched over `http` or `https` through Network, redirects followed; any other digest fails it. Its key is `sha256` alone |
| `extract(name, archive, format)` | the tree an `ArchiveFormat` holds: `Tar`, `TarGzip`, `TarXz`, `TarZstd` or `Ar`. A path climbing with `..`, or an entry under a link the archive made, fails it; a hard link becomes a copy |
| `decompress(name, file, compression)` | a file of `Gzip`, `Xz` or `Zstd` decompressed |
| `patch(name, tree, patches, strip)` | the tree with unified diffs applied in order as `patch -p<strip>` applies them, without fuzz: a hunk lands where its context is found whole, nearest where it says, or fails it. Git's file modes, `/dev/null` and `diff -N`'s empty files make and remove files |
| `cpio(name, tree)`, `gzip`, `zstd(name, file, level)` | an initramfs archive and its compression |
| `tar(name, tree)` | a POSIX ustar archive, pax headers holding the paths, link targets and sizes ustar cannot |
| `squashfs(name, tree, level)` | a read-only filesystem image, zlib at levels 1 to 9, every block stored as it is at level 0 |
| `composefs(name, tree)` | an EROFS image of the tree without its data: each file a hole of its size carrying its fs-verity digest and a redirect to its path in the tree, for overlayfs's `verity=require` with the tree as a data-only layer |
| `verityDigest(name, file)` | the file's fs-verity digest, SHA-256 over 4096-byte blocks with no salt, as 32 bytes: what the kernel answers for it once fs-verity is on |
| `sparse(name, length)` | a file of that many zero bytes, holding no storage where the filesystem allows: an empty disk image |
| `signingKey(path, create)` | not an action: the Ed25519 private key in a PEM or DER PKCS#8 file outside the store, read when the graph is built, and made there, readable by its owner alone, when it is missing and `create` holds. Its public half is `publicKey` |
| `sign(name, artifact, key)` | the Ed25519 signature of a file by a `signingKey`: 64 bytes, as RFC 8032 and `openssl pkeyutl -sign -rawin` make it. Its key holds the key's public half, never the private one |
| `concatenated(name, parts, mode)` | files one after another |
| `padded(name, artifact, multiple)` | a file with zero bytes after it up to a multiple of a length |
| `checked(name, artifact, check)` | the file unchanged, once a `FileCheck` passed on it: Kira code given the file's path, keyed by its `code` (`sourceDigest!()`) and `parameters`. `machineCheck(machine)` is one: an ELF file built for that `e_machine`, 62 for x86_64 and 183 for aarch64 |

A native action is handed each file input's permission bits in
`NativeRun.modes`, beside each tree input's entries in `NativeRun.trees`, and
the digest the store keeps each input under in `NativeRun.digests`. An action
that copies a stored file whole into an output, as `union`, `tree`, `subtree`,
`member`, `copy` and `checked` do, tells `NativeRun.copied` the output's path and the
digest it copied; the store takes that digest without reading the copy again.
Every packer is reproducible: entries in byte order of their paths, owner and
group 0, and timestamps 0. A packer's code is Build's own, so a better
compressor in Archive repacks once Build is edited to take it, and what is
downstream reruns only where the bytes it packed changed.

## 6. The engine

### 6.1 Content store and action cache

```
$KIRA_BUILD_CACHE (default ~/.cache/kira/build)/
  store/<2 hex>/<62 hex>        every output file, by SHA-256, read-only
  actions/<2 hex>/<62 hex>      an action record: its outputs and discovered inputs
  verified/<2 hex>/<62 hex>     empty: the store was found holding every file of
                                the tree with that digest
  projects/<64 hex>             what one project needs, by the SHA-256 of its root
  running/<64 hex>              locked by a build of that project while it works
  sweep                         locked while the cache is swept, and while a build
                                takes its running lock
<project>/.kira-build/
  lock                          locked by the one run working here; another
                                run waits for it, and it goes with the process
  out/<step>/                   what each requested step produced, as copies
  placed/<step>                 what out/<step> held once placed: placed again
                                only when an artifact or an entry there changed
  work/<key>/                   an action while it runs; kept when it fails
  workspaces/<name>/            a command's workspace, kept from run to run
  logs/<label>.out, .err        what each command last wrote
  status                        the stat cache of the project's sources
  last/<label>                  the key and inputs of each action's last run,
                                for --explain
```

An action key is the SHA-256 of the action's canonical Kten encoding with
every input replaced by its digest. A command's encoding holds its tool's
digest, and a native action's the digest of its code (section 5.2): the key
covers what runs as well as what it reads. A rerun whose outputs are the same
bytes as before leaves every key downstream as it was. A tree's digest is the digest of its
listing: each path, kind, permission bits and file digest, in byte order.

The stat cache maps a source path to its size, modification time, inode and
digest. A file whose first three are unchanged is not hashed again.

The store keeps every file read-only and none of them runnable, so one blob
serves every mode. A file is placed as a second name only when it need not run
and its reader is trusted (section 5.2); otherwise it is a copy under its mode.
A directory placed from a tree keeps its listed bits plus the owner's read,
write and search bits, so the build can fill and remove it.

### Relocatable source hierarchies

Commands remain path-sensitive by default. A command may opt in with
`sourceRoot`, a path relative to the graph root naming a source hierarchy
whose relocation preserves the outputs. KiraSettings forwards this option.
Declared reads within this hierarchy use `source:<relative path>` in the
key, with their content digest and mode unchanged. Reads outside it keep
absolute paths. The key includes the opt-in sourceRoot spelling.

Source scopes and depfile paths resolve filesystem symlinks before matching,
including missing suffixes. Thus `/var` and `/private/var` refer to the same
source hierarchy on macOS, and a dependency cannot accidentally stay attached
to the originating workspace through an absolute alias.

Discovered inputs within that hierarchy are recorded with a relative path
and a relative flag. A cache lookup resolves them against the current
command's sourceRoot, including absent paths and directory listings. External
discovered inputs remain absolute. Thus a sibling dependency edited in one
workspace cannot be validated against another workspace's sources.

Discovered-input variants use a final action key covering the declared-input
key and every discovered path, digest and relocation flag. The shared cache
indexes these final keys under `variants/<declared-key>/<final-key>`. Cache
lookups validate candidates against the current workspace. Each project's
last record and each snapshot retain the final key they actually used;
collection removes unreferenced variants and index entries. Workspaces with
different sibling dependency contents therefore cannot evict one another's
valid results.

### Immutable snapshots and shared views

A Step may supply `snapshot` metadata to pin its outputs and required action
records in `snapshots/<SHA-256>`. The digest covers the complete binary Kten
manifest. Pins are immutable and remain garbage collection roots even after
the originating project disappears. Invalid pins stop collection. Removing
an obsolete pin is an explicit release-management action.

`materialize: false` skips workspace output placement and requires snapshot
metadata or a callback. StepRun carries artifact references and the optional
snapshot digest. `loadBuildSnapshot` checks a manifest's digest and schema;
`Graph.reference` consumes a stored artifact by digest, kind and mode without
rebuilding its producer. Missing referenced artifacts fail the build.

`resolveBuildArtifact` places one shared view per digest and file mode under
`views/`, serialized against collection. Workspaces resolve identical
artifacts to the same path. Collection removes unreferenced shared views.
Consumers must treat these paths as immutable. `buildArtifactEntries` reads
a tree's manifest for consumers that pack only changed roots.

### 6.1.1 Sweeping the shared cache

The shared cache keeps only what some project needs. A project needs the
record under the key in each of its `last/` entries, every file of the
artifacts those entries read, and every file of the outputs those records
name, a tree's files through its listing.

Every build that takes the project's lock also takes `running/<project>`,
under `sweep`, and holds it while it works. Once a build has placed its
chosen steps, or has failed, it writes what its project needs to
`projects/<project>` from `last/`, lets `running/<project>` go and sweeps:
when `sweep` is free and no `running/` lock is held, it removes every action
record and every stored file that no `projects/` entry needs, then each
subdirectory left empty, and every `verified/` mark but those of the trees
whose listing it read and whose files it kept. A record is used only while
the store holds every file of its outputs; a tree with a mark is not looked
through again, so a cache hit on a large tree costs one lookup rather than
one per file. A `projects/` entry whose project has no
`.kira-build/` any more needs nothing and goes. When another build is at work
the sweep is left to the next one. `-dry-run` sweeps nothing.

`-clean` leaves the project's `projects/` entry as it was, so what it needed
stays until its next build says otherwise.

### 6.2 Scheduling

The scheduler starts at the requested steps, walks back to the actions they
need, and runs each one once all its inputs exist. `-jobs` (default: the
host's processor count) bounds the command actions running at once. Native
actions run on the scheduler's own thread between waits; running them on the
build's own tasks is for later. The scheduler waits on `child_wait_any`; it
never polls.

On a failure, nothing new starts, the running actions finish, and the build
reports every failure with the command, its working directory and the end of
its output. `-keep-going` keeps starting what does not depend on a failure.

### 6.3 Reporting

One line per action as it starts, `[12/40] library LibTessera
(x86_64-unknown-tessera)`, and its output only when it fails or `-verbose` is
given. Each action's full output is kept under `.kira-build/logs/`. Redrawing
the line in place under a terminal, as section 5.2.1 of the framework does, is
for later.

`-explain` prints, under each action that runs, why: it never ran in this
project, its outputs left the cache, the inputs that changed, or its
description or program changed. `-dry-run` prints `would run <label>` for
each action whose record is not in the cache, and for everything after it.

## 7. Command line

```
kira build [step...] [-option value...] [-jobs n] [-keep-going]
           [-dry-run] [-explain] [-graph] [-verbose] [-clean] [argument...]
kira build -o <out> <path>     a single compile, as before
kira build --emit <kind> ...   a single compile, as before
```

With `-o` or `--emit` the command is the compiler. Otherwise, when the nearest
directory at or above the working directory holding `build/package.kira` is a
project, the driver runs that package with the remaining arguments; outside a
project the command is the compiler. `kira build` with no step lists the steps
and options. The driver finds the project in `compatDriver`, through the KLF
Kira builtins `driverDirectory` and `driverPathExists` (framework D-389).

Every flag takes one dash; `--name` is refused. A flag is `-name value` or
`-name=value`; `-j N` and `-jN` are `-jobs`. The library reads its own flags,
and each option the graph declares takes its `-name value` from what is left.
The leading words that name a declared step are the steps, and everything
after them goes to the steps that run something (`StepRun.arguments`): in
`kira build boot -arch aarch64 -test`, `boot` is the step, `-arch` the
option, and `-test` the step's. A description that reads its step's arguments
before every step is declared uses `graph.passed(step)`, which is what follows
`step`, and declares its own options first. `-clean` removes what
`.kira-build/` holds but its lock before anything else, and leaves the shared
cache alone.

## 8. Archive and Elf

The Archive library (`std/Archive`) holds the formats, in Kira, for
anyone to use; Build's packers are actions over it.

| Format | Read | Write |
| --- | --- | --- |
| tar (ustar, pax, GNU long names) | yes | yes: ustar, with pax headers |
| ar (GNU and BSD names) | yes | no |
| cpio newc | yes | yes |
| squashfs 4.0 | no | yes: zlib or stored blocks, no fragments, no extended attributes |
| composefs (EROFS) | no | yes: metadata only, files as holes with overlayfs's metacopy and redirect attributes |
| fs-verity digests | of files and bytes | n/a |
| deflate, gzip, zlib | yes (on Foundation's inflate) | yes |
| zstd (every frame but those needing a dictionary) | yes | yes |
| xz (LZMA2, CRC-32 or CRC-64 checks) | yes | no |
| unified diffs | applied | no |

Readers stream: a tar is unpacked as its file is read, an xz file is decoded
one LZMA2 chunk at a time and a zstd file one block at a time, so a tarball
never sits whole in memory decompressed.

The zstd reader takes concatenated frames, passing over skippable ones, with
windows up to 2 GiB: raw, repeated and Huffman-coded literals in one stream or
four, sequences with predefined, repeated, described or the previous block's
tables, and repeat offsets. It keeps only the window a match may reach, and
checks each frame's content size and checksum.

The zstd writer makes one frame with its content size and checksum, in
128 KiB blocks over a 2 MiB window: matches from hash chains, deeper as the
level (1 to 19) rises, Huffman-coded literals with their weights
FSE-compressed, and repeat offsets. A block of 64 sequences or more describes
its own sequence distributions where they come out smaller than the
predefined ones. Lazy matching is for later.

The Elf library (`std/Elf`) reads 64-bit little-endian ELF, which x86_64
and aarch64 use, and splits an executable or shared library in two:

- `stripDebugInformation` leaves out every section named `.debug*`,
  `.zdebug*` or `.gdb_index`, the symbol table, the strings only it uses, and
  relocations of what goes. The segments' bytes are kept as they are, so the
  program runs as before; the sections kept outside them follow, each at its
  alignment, then a section name table rebuilt with shared tails, then the
  section headers, indices renumbered. Its section and program headers are
  those `llvm-strip --strip-unneeded` writes.
- `debugInformation` keeps every section header, at its address. A section
  that occupies memory keeps no bytes, but a note, which holds the build id.
  A section in a loaded segment keeps its place in that segment, the segment
  starting at the first offset past the sections before it that its address
  allows; the program headers say what of each segment is still in the file.
  This is `llvm-objcopy --only-keep-debug`'s layout, but that llvm can place a
  segment at an offset its address does not allow when another segment starts
  where it does; the symbol and string tables are kept as they are.

`interfaceStub` keeps a shared library's global and weak dynamic symbols of
default or protected visibility, sorted by name, each once, with the
libraries it needs and its soname: the header, `.dynsym`, `.dynstr`,
`.dynamic` and `.shstrtab`, each at an address equal to its offset, then the
section headers, as `llvm-ifs --output-elf` lays them out, strings ordered
from their ends with shared tails. A function's size is left out, a defined
symbol sits in section 1 and every value is 0. `DT_STRSZ` holds the size of
`.dynstr`, where `llvm-ifs` writes that of `.dynsym`. A name given twice with
another type or size, or a symbol of another type than none, object, function
or thread-local storage, fails it.

`elfMachine` answers a file's `e_machine`, for a check that a binary was
built for the architecture it is installed on.

## 9. Order of work

1. Kernel services (section 3), Foundation wrappers, knvm on Foundation.
2. Build: graph, store, cache, scheduler, report, command line, `kira build`.
3. Kira rules with `--depfile`.
4. Archive formats, then the library actions over them.
5. A project's port: the first is Tessera, whose `build/` package replaces its
   `scripts/` directory.
