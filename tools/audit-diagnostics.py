#!/usr/bin/env python3
"""Classifies every Kira DiagnosticSpec for docs/diagnostics-audit.md.

`--check` exits 1 unless every spec names a symbol and has a help or fix line.

The classes are heuristics over the spec table and the `report(.Case, span)`
sites in definitions/: a code is named at the span when a site passes a name
or identifier span, a title quotes a symbol itself, and an explanation says
what to write when it names a rule's fix.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "languages" / "kira"
FIX_WORDS = re.compile(
    r"\b(write|written|use|add|declare|move|give|make|pass|needs?|must|follow|followed|"
    r"name|state|put|take|import|export|mark|choose|become|hold|read|pick|return|mean|"
    r"is a|are)\b"
)


def specifications(language):
    return re.findall(
        r'DiagnosticSpec\s*\{\s*code\s*=\s*(\d+),\s*severity\s*=\s*\.(\w+),\s*title\s*=\s*"((?:\\.|[^"\\])*)",'
        r'\s*explanation\s*=\s*"((?:\\.|[^"\\])*)"(?:\s*,\s*help\s*=\s*"(?:\\.|[^"\\])*")?\s*\}',
        language,
    )


def report_sites(definitions):
    sites = {}
    for path in definitions.rglob("*.klfd"):
        for case, args in re.findall(r"report\(\.(\w+),\s*([^)]*?)\)", path.read_text()):
            sites.setdefault(case, []).append(args.strip())
    return sites


def main():
    language = (ROOT / "definitions/language.klfd").read_text()
    table = json.loads((ROOT / "definitions/diagnostic-registry.json").read_text())
    name_of_code = {str(row["code"]): row["name"] for row in table}
    sites = report_sites(ROOT / "definitions")
    # String-aware: explanations may contain braces, so scan each whole literal.
    with_help = {
        code for code, body in re.findall(
            r'DiagnosticSpec\s*\{\s*code\s*=\s*(\d+),((?:"(?:\\.|[^"\\])*"|[^"])*?)\}\s*,?\s*(?=DiagnosticSpec|\])',
            language)
        if re.search(r'\bhelp\s*=', body)
    }
    rows = []
    for code, severity, title, explanation in specifications(language):
        case = name_of_code.get(code)
        arguments = sites.get(case, []) if case else []
        if any(re.search(r"name|identifier|Identifier", argument) for argument in arguments):
            symbol = "named at the span"
        elif "`" in title:
            symbol = "static title names it"
        else:
            symbol = "missing symbol name"
        if code in with_help:
            help_ = "has a help line"
        elif FIX_WORDS.search(explanation):
            help_ = "explanation says what to do"
        else:
            help_ = "missing help/fix"
        raised = "in the registry" if case else "not in the registry"
        rows.append((int(code), severity, title, symbol, help_, raised))
    counts = {
        "specs": len(rows),
        "symbol": dict(Counter(row[3] for row in rows)),
        "help": dict(Counter(row[4] for row in rows)),
        "registry": dict(Counter(row[5] for row in rows)),
    }
    json.dump(counts, sys.stdout, indent=1)
    print()
    if "--check" not in sys.argv:
        return 0
    # Gate: every spec must name a symbol and carry a help or fix line.
    failing = [row for row in rows if row[3] == "missing symbol name" or row[4] == "missing help/fix"]
    for code, severity, title, symbol, help_, _ in failing:
        print(f"FAIL {code} {title}: {symbol}; {help_}", file=sys.stderr)
    if failing:
        print(f"audit --check: {len(failing)} spec(s) fail", file=sys.stderr)
        return 1
    print("audit --check: 0 missing symbol, 0 missing help", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
