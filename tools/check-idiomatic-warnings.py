#!/usr/bin/env python3
"""Check native Kira lint diagnostic precision without linking a runtime.

    python3 languages/klf-kira/tools/check-idiomatic-warnings.py \
        --kira /path/to/rebuilt/kira

The compiler must have been built from the matching Kira definition sources.
The full corpus remains the authoritative runtime test, but this provides a
fast, exact check of warning codes and line numbers even when native linking
or package dependencies are unavailable.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import subprocess

WARNING = re.compile(r"\.kira:(\d+):\d+: warning\[(\d+)\]:")
ERROR = re.compile(r"\.kira:(\d+):\d+: error\[(\d+)\]:")

FIXTURES = {
    "idiomatic-style-warnings.kira": {(6008, 4): 1, (6008, 5): 1, (6008, 6): 1, (6009, 7): 1},
    "typed-fallback-style.kira": {(6010, 13): 1, (6010, 23): 1, (6010, 28): 1, (6010, 33): 1},
    "constant-function-style.kira": {(6011, 3): 1, (6011, 4): 1, (6011, 5): 1},
    "silent-failure-style.kira": {(6012, 13): 1, (6012, 40): 1},
    "idiomatic-deep-expressions.kira": {(6008, 14): 1, (6008, 15): 1, (6008, 16): 1},
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kira", type=Path, required=True, help="rebuilt Kira compiler executable")
    parser.add_argument("--sources", type=Path,
                        default=Path(__file__).resolve().parent.parent / "languages/kira/corpus/sources")
    args = parser.parse_args()
    failures = 0
    for fixture, expected in FIXTURES.items():
        file = args.sources / fixture
        result = subprocess.run([str(args.kira.expanduser().resolve()), "check", str(file), "--timings"],
                                capture_output=True, text=True, check=False)
        output = result.stdout + "\n" + result.stderr
        actual = Counter((int(code), int(line)) for line, code in WARNING.findall(output))
        errors = ERROR.findall(output)
        success = result.returncode == 0 and not errors and actual == Counter(expected)
        if success:
            print(f"PASS {fixture}: {sum(actual.values())} exact warning(s)")
        else:
            failures += 1
            print(f"FAIL {fixture}: exit={result.returncode}, errors={errors}")
            print(f"  expected: {Counter(expected)}")
            print(f"  actual:   {actual}")
            print(output[-3000:])
    print(f"{len(FIXTURES) - failures}/{len(FIXTURES)} fixture checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
