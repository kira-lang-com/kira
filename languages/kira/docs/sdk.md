# SDKs and per-target dependencies

A package builds against an SDK without spelling where the SDK lives, and a
dependency says where it comes from on a target that has no such SDK. Both are
resolved by the launcher (`kira` on `PATH`, `tools/launcher`, with
`tools/knvm-core/app/Sdk.kira`) before it hands the compile to the selected
toolchain.

## Where SDKs are found

An SDK is a directory `<root>/<Name>/<version>/` holding `SDKSettings.json` and
`System/Library/Frameworks/` (KLF-RIDL section 27.7; `tessera/roadmap/18-components.md`).

The roots, in order:

- `KIRA_SDK_PATH`, a list separated by `:` as `PATH` is. When set it replaces the
  default.
- otherwise `<KLFD_HOME or ~/.klf>/sdks`.

Tessera's SDK, once built, is installed as `~/.klf/sdks/Tessera/<version>/`.

## Naming an SDK

A package names its SDK in its `package.kira`:

```
construct Core extends Package {
    let sdk: String = "Tessera"
}
```

or else the nearest `kira-sdk.toml` at or above the package directory does:

```
name = "Tessera"
version = "0.1.0"    # optional; needed when more than one is installed
```

`project-matter/kira-sdk.toml` names Tessera for the whole repository, so no
package there spells a path or a name.

For a compile verb (`build`, `check`, `test`, `run`, `doc`) the launcher adds
`--sdk <path>` when the named SDK is installed. A `--sdk` given on the command
line is kept.

## Dependencies with an SDK case and another case

A dependency names the SDK that may provide it and at least one other case:

```
Dependency { name: "Ember", sdk: "Tessera", path: "../ember" }
Dependency { name: "Ember", sdk: "Tessera", url: "git@github.com:kira-lang-com/ember.git", rev: "51babdb344bbd4b79ede7e05ee1407cbfa66a765" }
```

Selection is deterministic:

1. If the SDK is resolved and holds `<Name>.framework`, the framework is the
   dependency (the compiler's existing rule, KLF-RIDL 27.7 rule 3).
2. Otherwise `path` is used when given, relative to the package.
3. Otherwise `url` at `rev` is fetched by the launcher into
   `<KLFD_HOME>/git/<name>/<rev>` (once; a rev names one immutable commit) and
   handed to the compiler as `--dependency Name=<directory>`.

A dependency with no `sdk` is as before: `path`, or a `url` with a `rev` fetched
the same way. A `path` always wins over a `url`, so a checkout beside the package
is used on a developer machine and the pinned commit elsewhere.

## Diagnostics

Launcher diagnostics carry `SDK` codes, and name the file they came from:

| Code | Level | Meaning |
| --- | --- | --- |
| SDK0001 | note | the named SDK is not installed; the other cases are used. It names every searched root |
| SDK0002 | error | the name matches more than one installed SDK; pin the `version` |
| SDK0003 | error | a `kira-sdk.toml` names no SDK |
| SDK0004 | error | a dependency has an `sdk` and no other case; add `path` or `url` with `rev` |
| SDK0005 | error | a git dependency could not be fetched; the cache directory is named |
| SDK0006 | note | a dependency is not in the SDK here; its other case is used |
| SDK0007 | error | a git dependency names no `rev` |

Each error ends with a `= help:` line. A missing SDK is a note because a
package that has the other cases builds without it, as on macOS.

## Limits

- Only the package being compiled has its dependencies resolved by the launcher.
  A dependency of a dependency that names a `url` is not fetched by this
  mechanism; it needs its own `path` checkout.
- `--dependency` matches by dependency name, so the same name at two places in
  the graph gets the same checkout.
- The compiler itself does not read `sdk`, `url`, `rev` or `tag`. It accepts them
  so the manifest parses, and runs without the launcher only for the `path` and
  SDK cases.

## Producing an SDK: what Tessera's build must write

`tessera/scripts/build-component.sh` does not exist yet, so no Tessera SDK is
built and nothing installs one. Its contract, as this doc needs it:

- For each architecture `<arch>` it writes `out/<arch>/Tessera.sdk/` (public
  frameworks only) and `out/<arch>/Tessera.Internal.sdk/` (plus the private
  frameworks, for components on the system volume list), as
  `roadmap/18-components.md` section 2 lays out.
- Each holds `SDKSettings.json` (name, version, architecture, target triple)
  and `System/Library/Frameworks/<Module>.framework/` with the stripped library
  `<Module>` and its contract `Resources/<Module>.ridl`.
- Installing it means copying the SDK to `<KLFD_HOME>/sdks/Tessera/<version>/`
  (or any root on `KIRA_SDK_PATH`). The version is the one in `SDKSettings.json`,
  and `kira-sdk.toml` pins it when more than one is installed.
- The sysroot (`KLF_SYSROOT`) is not part of the SDK. Only the frameworks are.

Until that script exists, `knvm sdk list` shows nothing for Tessera, and a
package that names it gets the SDK0001 note and its other cases, as on macOS.
