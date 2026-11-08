# 26.11.1

**Project:** KLF-hosted Kira frontend  
**Release week:** 2026-11-02 – 2026-11-08

## Highlights

Updated the KLF-hosted Kira definitions and low-level safety checks.

## Changed

- Migrated language definition sources from `.klfd` to `.kcore` in the KLF/Kira integration.
- Expanded Kira syntax, semantic checks, diagnostics, and Foundation/Heap implementation sources.
- Added parser and checker paths for `unsafe` statements, unsafe callable declarations, foreign calls, raw-pointer operations, and native-state access.
- Fixed exponential native-state type checking for shared nested structs and enums by keeping one visited set across all branches of eligibility and user-`Drop` analysis. Added a 20-level diamond-graph regression.

## Known limitations

- Full compatibility with the Rust reference compiler, end-to-end application builds, and exhaustive unsafe-boundary regression tests have not been verified for this preparation.
- Unsafe syntax and semantic boundaries are implemented and documented in `languages/kira/docs/subset.md`; exhaustive cross-compiler negative-test and indirect-call parity remain unverified.
