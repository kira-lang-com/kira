#!/bin/sh
# `kira doc` over unchanged sources must print the documentation on every run.
# The documentation is written while the package elaborates, and the framework's
# query cache answers a repeat run's `lower` query from its entry, skipping
# elaboration and so the output (karc-work notes: KLF-DISK query cache,
# klf-frontend-rt module_cache.rs). This script fails until that is fixed in the
# framework; doc-golden.sh holds everything else.
set -eu
packages=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

kira doc "$packages/documentation" | grep -v '^Check: Ok$' > "$work/first.md"
kira doc "$packages/documentation" | grep -v '^Check: Ok$' > "$work/again.md"
diff "$packages/documentation/expected-doc.md" "$work/first.md"
diff "$packages/documentation/expected-doc.md" "$work/again.md"
echo "doc cache golden: ok"
