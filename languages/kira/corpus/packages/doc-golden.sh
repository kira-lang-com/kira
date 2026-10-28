#!/bin/sh
# Golden checks for `kira doc` (languages/kira/docs/documentation.md), run from
# anywhere:
# - the Markdown of corpus/packages/documentation matches expected-doc.md;
# - the JSON of documentation-members matches expected-doc.json;
# - `kira doc --check` passes on both packages, and on documentation-missing it
#   fails with one error 2103 per undocumented public declaration or member,
#   matching expected-check.txt (paths shortened);
# - an unknown --format is error 2104;
# - intra-doc links render, and doc-broken-links reports error 2106 per broken
#   link and error 2107 for its failing example (expected-check.txt).
# doc-cache-golden.sh checks repeat runs, which the query cache answers.
set -eu
packages=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# kira's check phase ends each run with a status line, which is not documentation.
kira doc "$packages/documentation" | grep -v '^Check: Ok$' > "$work/doc.md"
diff "$packages/documentation/expected-doc.md" "$work/doc.md"

kira doc --format json "$packages/documentation-members" | grep -v '^Check: Ok$' > "$work/members.json"
diff "$packages/documentation-members/expected-doc.json" "$work/members.json"

kira doc --check "$packages/documentation" > "$work/own.txt" 2>&1
if grep -q 'error\[2103\]' "$work/own.txt"; then
    echo "documentation: undocumented public API" >&2
    exit 1
fi
kira doc --check "$packages/documentation-members" > "$work/members.txt" 2>&1
if grep -q 'error\[2103\]' "$work/members.txt"; then
    echo "documentation-members: undocumented public API" >&2
    exit 1
fi

status=0
kira doc --check "$packages/documentation-missing" > "$work/missing.txt" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "documentation-missing: --check passed, expected failure" >&2
    exit 1
fi
sed "s#^.*/app/#app/#" "$work/missing.txt" | grep 'error\[2103\]' | sed 's/: error\[2103\].*/ error[2103]/' > "$work/missing-short.txt"
diff "$packages/documentation-missing/expected-check.txt" "$work/missing-short.txt"

status=0
kira doc --format xml "$packages/documentation" > "$work/format.txt" 2>&1 || status=$?
if [ "$status" -eq 0 ] || ! grep -q 'error\[2104\]' "$work/format.txt"; then
    echo "--format xml: expected error 2104" >&2
    exit 1
fi
# Intra-doc links and doctests (docs/documentation.md).
kira doc "$packages/doc-links" | grep -v '^Check: Ok$' > "$work/links.md"
diff "$packages/doc-links/expected-doc.md" "$work/links.md"

kira doc --check "$packages/doc-links" > "$work/links-check.txt" 2>&1 || {
    echo "doc-links: --check failed" >&2
    cat "$work/links-check.txt" >&2
    exit 1
}
rm -rf "$packages/doc-links/.kira-doctests"

status=0
kira doc --check "$packages/doc-broken-links" > "$work/broken.txt" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "doc-broken-links: --check passed, expected failure" >&2
    exit 1
fi
sed "s#^.*/app/#app/#" "$work/broken.txt" | grep -E 'error\[210[67]\]' | sed 's/: error\[\(210[67]\)\].*/ error[\1]/' > "$work/broken-short.txt"
diff "$packages/doc-broken-links/expected-check.txt" "$work/broken-short.txt"
rm -rf "$packages/doc-broken-links/.kira-doctests"

echo "doc golden: ok"
