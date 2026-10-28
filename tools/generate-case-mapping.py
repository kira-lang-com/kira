#!/usr/bin/env python3
"""Writes Foundation's case tables, std/Foundation/app/text/StringCaseTables.kira.

The tables are Unicode's full case mapping and the two properties its
Final_Sigma rule reads, Cased and Case_Ignorable, taken from the Unicode
database this Python carries. Run it again when that database moves on.
"""

import sys
import unicodedata
from pathlib import Path

LAST = 0x10FFFF
SIGMA = "Σ"
OUT = Path(__file__).resolve().parent.parent / "languages/kira/std/Foundation/app/text/StringCaseTables.kira"


def scalars():
    for scalar in range(LAST + 1):
        if 0xD800 <= scalar < 0xE000:
            continue
        yield scalar


def mappings(convert):
    """The scalar to scalar mappings, and the ones to more than one scalar."""
    single = {}
    expanded = {}
    for scalar in scalars():
        character = chr(scalar)
        # Sigma alone lowercases to the medial form; the final form is
        # the rule's, in the code, not the table's.
        mapped = convert(character)
        if mapped == character:
            continue
        if len(mapped) == 1:
            single[scalar] = ord(mapped)
        else:
            expanded[scalar] = [ord(part) for part in mapped]
    return single, expanded


def runs(single):
    """Runs of scalars mapped by one offset: consecutive, or every other one
    with the scalars between them left as they are."""
    keys = sorted(single)
    result = []
    index = 0
    while index < len(keys):
        start = keys[index]
        delta = single[start] - start
        # Consecutive.
        end = start
        while end + 1 in single and single[end + 1] - (end + 1) == delta:
            end += 1
        if end > start:
            result.append((start, end + 1, 1, delta))
            index = keys.index(end) + 1
            continue
        # Every other one.
        end = start
        while (end + 2 in single and single[end + 2] - (end + 2) == delta
               and end + 1 not in single):
            end += 2
        if end > start:
            result.append((start, end + 1, 2, delta))
            index = keys.index(end) + 1
            continue
        result.append((start, start + 1, 1, delta))
        index += 1
    return result


def ranges(members):
    """The members as runs of consecutive scalars, each end exclusive."""
    result = []
    for scalar in members:
        if result and result[-1][1] == scalar:
            result[-1][1] = scalar + 1
        else:
            result.append([scalar, scalar + 1])
    return result


def hexadecimal(value):
    return "0x%X" % value


def pattern(start, end):
    if end == start + 1:
        return hexadecimal(start)
    return "%s..%s" % (hexadecimal(start), hexadecimal(end))


def mapping_function(name, comment, single):
    lines = ["// " + line for line in comment]
    lines.append("function %s(scalar: Int) -> Int {" % name)
    lines.append("    match scalar {")
    for start, end, stride, delta in runs(single):
        offset = ("scalar + %d" % delta) if delta >= 0 else ("scalar - %d" % -delta)
        if stride == 1:
            lines.append("        %s -> return %s" % (pattern(start, end), offset))
        else:
            lines.append("        %s -> return (scalar - %s) %% 2 == 0 ? %s : scalar"
                         % (pattern(start, end), hexadecimal(start), offset))
    lines.append("        else -> return scalar")
    lines.append("    }")
    lines.append("}")
    return lines


def expansion_function(name, comment, expanded):
    lines = ["// " + line for line in comment]
    lines.append("function %s(scalar: Int) -> [Int]? {" % name)
    lines.append("    match scalar {")
    for scalar in sorted(expanded):
        parts = ", ".join(hexadecimal(part) for part in expanded[scalar])
        lines.append("        %s -> return .Some([%s])" % (hexadecimal(scalar), parts))
    lines.append("        else -> return .None")
    lines.append("    }")
    lines.append("}")
    return lines


def property_function(name, comment, members):
    lines = ["// " + line for line in comment]
    lines.append("function %s(scalar: Int) -> Bool {" % name)
    lines.append("    match scalar {")
    patterns = [pattern(start, end) for start, end in ranges(members)]
    for index in range(0, len(patterns), 6):
        lines.append("        %s -> return true" % ", ".join(patterns[index:index + 6]))
    lines.append("        else -> return false")
    lines.append("    }")
    lines.append("}")
    return lines


def main():
    lower_single, lower_expanded = mappings(str.lower)
    upper_single, upper_expanded = mappings(str.upper)
    # Final_Sigma: a sigma is final after a cased scalar, past any
    # case-ignorable ones, with none after it. Python applies the same rule,
    # so a scalar is cased (and not skipped) when a sigma after it alone is
    # final, and skipped when a sigma after it and a cased letter is final
    # though the scalar is not cased.
    cased = []
    ignorable = []
    for scalar in scalars():
        character = chr(scalar)
        if character == SIGMA:
            continue
        alone = (character + SIGMA).lower().endswith("ς")
        after = ("A" + character + SIGMA).lower().endswith("ς")
        if alone:
            cased.append(scalar)
        elif after:
            ignorable.append(scalar)

    out = [
        "// Unicode's full case mapping, and the properties its Final_Sigma rule",
        "// reads. Generated by tools/generate-case-mapping.py from Unicode %s."
        % unicodedata.unidata_version,
        "// Do not edit.",
        "",
    ]
    out += mapping_function("lowercaseScalar", [
        "The scalar `scalar` lowercases to, when it lowercases to one; itself",
        "otherwise.",
    ], lower_single)
    out.append("")
    out += expansion_function("lowercaseExpansion", [
        "The scalars `scalar` lowercases to, when it lowercases to more than one.",
    ], lower_expanded)
    out.append("")
    out += mapping_function("uppercaseScalar", [
        "The scalar `scalar` uppercases to, when it uppercases to one; itself",
        "otherwise.",
    ], upper_single)
    out.append("")
    out += expansion_function("uppercaseExpansion", [
        "The scalars `scalar` uppercases to, when it uppercases to more than one.",
    ], upper_expanded)
    out.append("")
    out += property_function("isCasedScalar", [
        "Whether `scalar` is Cased and not Case_Ignorable: the letter a final",
        "sigma follows.",
    ], cased)
    out.append("")
    out += property_function("isCaseIgnorableScalar", [
        "Whether `scalar` is Case_Ignorable: passed over looking for the letter",
        "before or after a sigma.",
    ], ignorable)
    OUT.write_text("\n".join(out) + "\n")
    print("wrote %s" % OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
