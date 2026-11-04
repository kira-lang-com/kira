# 26.11.1

**Project:** KLF-hosted Kira frontend  
**Release week:** 2026-11-02 – 2026-11-08

## Highlights

Updated the KLF-hosted Kira definitions and low-level safety checks.

## Changed

- Migrated language definition sources from `.klfd` to `.kcore` in the monorepo's KLF/Kira integration.
- Expanded Kira syntax, semantic checks, diagnostics, and Foundation/Heap implementation sources.
- Added parser and checker paths for `unsafe` statements, unsafe callable declarations, foreign calls, raw-pointer operations, and native-state access.

## Known limitations

- Full compatibility with the Rust reference compiler, end-to-end application builds, and exhaustive unsafe-boundary regression tests have not been verified for this preparation.
- `languages/kira/docs/subset.md` still describes unsafe parity as pending and must be reconciled with the new implementation before parity can be claimed.
