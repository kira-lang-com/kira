#!/usr/bin/env python3
"""Cross-check the external idiom sweep against the current Tessera checkout.

This is an evidence inventory, not a replacement for Kira's typed diagnostics.
Candidate labels deliberately do not assert a defect without semantic proof.
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
from pathlib import Path

FINDING = re.compile(r"^(?P<path>[^:]+\.kira):(?P<line>\d+): \[(?P<rule>[^]]+)\] (?P<reason>.*)$")
EVIDENCE_PATH = re.compile(r"(?:apps|kira-packages|tessera-packages|infrastructure|languages)/[\w./-]+\.kira")
REVIEW_HEADING = re.compile(r"^### (\d+)\. (.*)$")


def read_sweep(sweep: Path):
    """Parse paired diagnostic/source lines without treating the snippet as current."""
    lines = sweep.read_text(encoding="utf-8").splitlines()
    findings = []
    for n, text in enumerate(lines):
        match = FINDING.match(text)
        if not match:
            continue
        fields = match.groupdict()
        snippet = lines[n + 1].strip() if n + 1 < len(lines) else ""
        findings.append({"path": fields["path"], "line": int(fields["line"]),
                         "rule": fields["rule"], "reason": fields["reason"],
                         "original_snippet": snippet})
    return findings


def read_review(review: Path):
    """Locate review findings by cited files, not by unreliable titles."""
    hits = collections.defaultdict(list)
    current = None
    for line in review.read_text(encoding="utf-8").splitlines():
        heading = REVIEW_HEADING.match(line)
        if heading:
            current = {"number": int(heading.group(1)), "title": heading.group(2)}
        elif current and line.startswith("**Evidence:**"):
            for path in set(EVIDENCE_PATH.findall(line)):
                hits[path].append(current)
    return hits


def candidate(rule: str, source: str, context: str) -> str:
    """Mark where semantic analysis is needed; never assert a confirmed bug."""
    if rule == "numeric-type":
        if source.startswith("enum ") or source.startswith("case "):
            return "numeric-lexical-not-type"
        if re.search(r"\b(?:U|I|N|UN|Float)(?:8|16|32|64|128)\b", source):
            return "numeric-explicit-width-needs-boundary-review"
        if "@FFI" in context or "@Foreign" in context:
            return "numeric-declared-foreign-boundary"
        if re.search(r"\bInt\b", source):
            return "numeric-int-role-needs-type-and-use"
        return "numeric-needs-resolved-type"
    if rule == "sentinel":
        if re.search(r'\breturn\s+""', source):
            return "empty-text-needs-result-vs-optional"
        if re.search(r"\breturn\s+-1\b", source):
            return "negative-sentinel-needs-callsite-proof"
        return "sentinel-needs-contract"
    if rule == "bare-otherwise-return":
        return "otherwise-needs-typed-error-contract"
    if rule == "error-failed-boilerplate":
        return "error-variant-needs-error-enum-context"
    if rule == "bool-helper":
        return "bool-operation-needs-result-flow"
    return "unknown-rule"


def annotate(findings, root: Path, review_hits):
    cached = {}
    for finding in findings:
        path = finding["path"]
        if path not in cached:
            location = root / path
            cached[path] = location.read_text(encoding="utf-8").splitlines() if location.is_file() else None
        lines = cached[path]
        line_number = finding["line"]
        source = lines[line_number - 1].strip() if lines and 0 < line_number <= len(lines) else ""
        surrounding = "\n".join(lines[max(0, line_number - 7):min(len(lines), line_number + 5)]) if lines else ""
        if lines is None:
            drift = "missing-source"
        elif source == finding["original_snippet"]:
            drift = "exact"
        elif finding["original_snippet"] in [line.strip() for line in lines[max(0, line_number - 4):min(len(lines), line_number + 3)]]:
            drift = "moved-nearby"
        else:
            drift = "changed"
        finding.update({"current_snippet": source, "status": drift,
                        "candidate": candidate(finding["rule"], source, surrounding),
                        "review_ids": [review["number"] for review in review_hits.get(path, [])]})
    return findings


def summary(findings):
    by_rule = collections.Counter(f["rule"] for f in findings)
    by_status = collections.Counter(f["status"] for f in findings)
    by_candidate = collections.Counter(f["candidate"] for f in findings)
    reviewed = {i for finding in findings for i in finding["review_ids"]}
    return {"total": len(findings), "files": len({f["path"] for f in findings}),
            "rules": dict(sorted(by_rule.items())), "source_status": dict(sorted(by_status.items())),
            "candidates": dict(sorted(by_candidate.items())),
            "distinct_review_items_in_overlapping_files": len(reviewed)}


def write_report(out: Path, findings, stats):
    out.mkdir(parents=True, exist_ok=True)
    with (out / "sweep-findings.csv").open("w", encoding="utf-8", newline="") as handle:
        keys = ["path", "line", "rule", "status", "candidate", "original_snippet", "current_snippet", "reason", "review_ids"]
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        for finding in findings:
            writer.writerow({key: ",".join(map(str, finding[key])) if key == "review_ids" else finding[key] for key in keys})
    (out / "sweep-summary.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    headings = ["# Original idiom sweep, revalidated against current Tessera sources", "",
                "This report is a **triage inventory**, not 7,226 confirmed bugs. A `candidate`",
                "label explicitly requires semantic/type/API evidence before a diagnostic.", "",
                f"- Findings: **{stats['total']:,}** across **{stats['files']:,}** flagged files.",
                f"- Source alignment: {stats['source_status']}.",
                f"- Items in the separate semantic review with a cited file overlapping the sweep: {stats['distinct_review_items_in_overlapping_files']} (file-level, not finding-level matching).",
                "", "## Original rule distribution", "",
                "| Rule | Count |", "| --- | ---: |"]
    for label, count in sorted(stats["rules"].items(), key=lambda x: -x[1]):
        headings.append(f"| `{label}` | {count:,} |")
    headings.extend(["", "## Classification of current evidence", "",
                     "| Evidence group (not a finding of fault) | Count |", "| --- | ---: |"])
    for label, count in sorted(stats["candidates"].items(), key=lambda x: -x[1]):
        headings.append(f"| `{label}` | {count:,} |")
    headings.extend(["", "## Why default rules must use semantics", "",
                     "- Numeric spellings can be enum cases, collection indices, native ABI widths or domain quantities. Prefer resolved symbol and type information.",
                     "- A return of `\"\"` can be a legitimate UI or serialization value; `Result`-typed `otherwise` and `Optional`-typed `otherwise` mean different things.",
                     "- A Bool-valued predicate is idiomatic, but an operation's success/failure should generally be a typed Result. Return types alone do not prove the latter.",
                     "- Names such as `Error(.Failed)` may denote a properly typed error case; do not rewrite on spelling alone.",
                     "- The distinct semantic review remains the human-verified authority for ownership, state machines, abstraction boundaries and cross-callsite problems.",
                     "", "## Repeat", "", "```sh", "python3 languages/klf-kira/tools/triage-idiomatic-sweep.py --root . --sweep ~/Cairn/kira-result-rule-sweep-2026-11-03.txt --review ~/Cairn/tessera-kira-idiomatic-code-review-2026-11-03.md --out ~/Cairn/kira-lint-triage-2026-11-05", "```", ""])
    (out / "README.md").write_text("\n".join(headings), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--sweep", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    findings = annotate(read_sweep(args.sweep), args.root, read_review(args.review))
    stats = summary(findings)
    write_report(args.out, findings, stats)
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
