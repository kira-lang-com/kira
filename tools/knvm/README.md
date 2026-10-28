# knvm, the Kira version manager

`knvm` provisions toolchains into `~/.klf/toolchains`, one tree per compiler,
selects one of each, and puts a launcher on PATH per compiler (`kira`, `ksl`,
`klf`) that dispatches to that compiler's selected toolchain. A verb acts on
the default language unless a compiler is named first: `knvm ksl list`,
`knvm klf install latest`. `klf` and every language come from their GitHub
releases (`kira-lang-com/kira-language-framework`, `kira-lang-com/kira`);
`binstall` builds this checkout's languages with the installed `klf`.

```
tools/knvm-core/       the logic, a library: layout, verbs, install, digest, feed
tools/knvm/            the `knvm` binary
tools/launcher/        the launcher on PATH for every compiler: resolve the selection, dispatch
```

## What it does

| Verb | What it does |
| --- | --- |
| `install <version\|latest> [--channel]` | Fetch a release, lay it down, select it |
| `list [--remote]` | What is installed, or what each channel publishes |
| `use <version> [--channel]` | Select an installed version |
| `pin <version> [--channel]` | Pin this directory tree to a version |
| `unpin` | Remove this directory tree's pin |
| `uninstall <version> [--channel]` | Remove an installed version |
| `setup` | Install the newest release of `klf` (then run its `klf setup`), of every language, and of `knvm` with its launchers, onto PATH; on an existing install, bring each up to date |
| `binstall` | Build every language the enclosing `toolchain.klfd` lists, register it, and install it as its dev toolchain |
| `sinstall` | Build `knvm` and a launcher per compiler from this checkout and put them on PATH |
| `valgrind install --target <triple> --sysroot <dir>` | Build the pinned Valgrind release for a Linux target with the selected `klf` toolchain's clang against that sysroot, and keep it at `~/.klf/tools/valgrind/<version>/<target>/`, a root whose `usr/lib/valgrind` is the prefix it was built for |

A bare `knvm` is the usage text with a first-run greeting; `help`, `--help` and
`-h` print it alone. Exit 0 when the operation ran, 1 when it was understood and
failed, 2 when the invocation was not understood.

## The layout

Everything derives from `KLFD_HOME`, which is `~/.klf` unless it is set, and it
never falls through when it is: an override that merged the two would let a test
write into a developer's real state.

```
$KLFD_HOME/
  env                          sourced by the shell startup file, prepends bin to PATH
  bin/knvm, bin/<binary>       the tools `sinstall` builds; each `<binary>` is the launcher
  toolchains/
    <compiler>/
      language.toml            the registration `binstall` writes (not for `klf`)
      current.toml             channel, version — what the launcher reads
      <channel>/<version>/     an installed toolchain
        bin/<binary>           the driver
        ...                    what the manifest copies: `definitions/` and `std/`
                               for kira, `share/ksl/library` for ksl
    .staging/<pid>/            where an install is unpacked before it is landed
  sdks/<Name>/<version>/       an SDK, found by name by the launcher (KIRA_SDK_PATH
                               replaces this root); languages/kira/docs/sdk.md
  git/<name>/<rev>/            a dependency's checkout at its pinned rev, fetched once
```

`KLF_HOME` is deliberately *not* this variable: that is the framework's own,
holding its kernel archives and its provisioned LLVM, and a toolchain tree is
neither. Sharing one would let an install write into the framework's state and
leave the framework reading a directory whose shape it does not know.

A pin is a `<compiler>-toolchain.toml` in a directory: the same two fields
`current.toml` carries, minus `primary`, because a pin says which toolchain, not
which binary inside it. The launcher prefers the nearest pin above the working
directory, and refuses a pin whose toolchain is not installed rather than
silently running the global selection.

## What an install does

`install` resolves `latest` by listing the channel, fetches the archive into a
staging directory that belongs to this process alone, checks it against the
published SHA-256, unpacks it with `tar`, validates the tree, and moves it into
place with a single `rename`. So a failed or interrupted install leaves no
half-toolchain a launcher could dispatch to, and the staging directory is removed
on every path out.

A checksum *mismatch* fails the install. An *absent* sidecar only downgrades it
to unverified, which is reported out loud — "verified" and "no checksum was
published" are different installs, and a user who cannot tell them apart has no
way to notice the day verification stops happening.

An already-installed version is validated and selected without a fetch, and
`install` always implies `use`. Uninstalling the selected version clears the
selection rather than repointing it: guessing a replacement would silently change
which compiler a user runs.

## Where releases come from

`KNVM_<NAME>_RELEASE_DIR` (`KNVM_KIRA_RELEASE_DIR`, `KNVM_KSL_RELEASE_DIR`, `KNVM_KLF_RELEASE_DIR`) names a local directory laid out exactly as a published feed:

```
$KNVM_KIRA_RELEASE_DIR/<channel>/<version>/kira-<version>-<host-key>.tar.gz
                                       kira-<version>-<host-key>.tar.gz.sha256
```

That is the offline route and the one the corpus drives; without it, releases
come from `kira-lang-com/kira` over `curl`, with `GH_TOKEN` or `GITHUB_TOKEN`
sent when the URL is GitHub's. The host key in those names is the framework's,
from `klf.host` — `x86_64-linux-gnu`, `aarch64-macos`, and so on.

## binstall and sinstall

`binstall` is the developer route. Run bare, anywhere in a repository of
languages, it reads the `toolchain.klfd` at that repository's root and, for every
language listed there, runs `klf build <path> -o <staging>/bin/<binary>`, copies
each `files` entry from the language package into the toolchain, lands the result
on the `dev` channel through the same staging, validate and rename pipeline a
release install uses, and records the language in
`$KLFD_HOME/toolchains/<name>/language.toml`. That record is the registry: every
later `knvm` invocation and every launcher knows the language from it. The
toolchain is named after the version `<path>/definitions/language.klfd` declares.
`knvm <name> binstall` builds one listed language. A second run replaces the
tree: a dev toolchain names a moving target, so "already installed" would mean
"silently stale".

A language build has no `--debug`, because `klf build` links the driver at the one profile it
has and there is nothing for a flag to choose.

`sinstall` builds `tools/knvm` and `tools/launcher` with the selected
toolchain's own driver — a machine that installed one needs no second compiler —
and lands them in `$KLFD_HOME/bin` as `knvm` and one launcher per registered
compiler (`kira`, `ksl`, `klf`). A language registered after the last
`sinstall` has no launcher until `sinstall` runs again; `binstall` says so. The startup file is
chosen from `$SHELL`: `.zshenv` for zsh, `.bashrc` for bash, `.profile` otherwise,
because a line in a file the shell never reads configures nothing. Everything is
idempotent, and a tool that is already installed is renamed aside rather than
deleted, since the running `knvm` holds its own file open.

## Running the checks

`languages/kira/corpus/packages/knvm` covers the decisions a version manager rests on: the
digest against its NIST vectors and the block boundaries a streaming hasher gets
wrong, version ordering, the state files and what a file that is not one of them
is answered as, every verb and every refusal, and a release feed read from canned
text. `klf test . --corpus packages` runs it.

What needs a network, a built driver or a real toolchain tree — `binstall`,
`sinstall`, an install from a feed — is exercised by running it, not by a case.

## Where this stops

`install-llvm`, `install libffi` and `self-update` are not here. The first two
provision things that belong to the framework: its LLVM bundle and its libffi
archives are version-independent siblings shared across toolchains, keyed by
their own versions, and a toolchain install must not touch them. `self-update`
replaces `knvm` itself, which `sinstall` already does out of a checkout.

Every operation these programs perform is a `klf.*` kernel service: the
filesystem, the environment, the arguments, the output and the child processes
all come from the platform, and none of them is reached by a raw system call.
Running a tool is `klf.process.command_push` / `command_run` / `output`, which
also means the service searches `PATH` itself — so this tool never resolves an
executable, and "-2" from a run is how it learns a tool is not installed.

The host key is the framework's, read through `klf.host` — the same
`<arch>-<os>` string the framework names its own provisioned bundles by, so a
machine is spelled one way across the whole toolchain tree. It used to be derived
here from `uname`, which was a raw syscall in an application: the wrong layer for
it, since nothing above the kernel names the machine and the answer belongs to
the platform. `tools/knvm-core` now contains no `@FFI.Syscall` at all.

One consequence worth naming: the launcher runs the driver as a child and waits
for it, where the Rust launcher replaces its own image. A program here reaches
the kernel through services answered by its own runtime, so a replaced image
would have none. The driver still gets this program's own streams, arguments and
environment, and its exit status is this process's — but a driver stopped by a
signal is reported rather than dying the same way.
