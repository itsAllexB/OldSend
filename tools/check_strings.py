#!/usr/bin/env python3
"""Fails the build if the app's strings can crash it or show nonsense.

Every language must have the same keys, and each key must take the same arguments in the same
order, once positions like %2$d are worked out. A format with %d and %@ the other way round from
its call sends a number where an object is expected, and the app crashes: that was OldSend 2.1's
crash on receiving more than 3 photos, in English only.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
SPEC = re.compile(r"%(?:(\d+)\$)?(?:l|ll|h)?([@dsuxXf%])")


def arguments(text):
    """The argument kinds in order; a positional format is sorted into call order."""
    plain, positional = [], {}
    for position, kind in SPEC.findall(text):
        if kind == "%":
            continue
        kind = "d" if kind in "duxX" else kind
        if position:
            positional[int(position)] = kind
        else:
            plain.append(kind)
    if positional and plain:
        return ["mixed"]
    if positional:
        return [positional[i] for i in sorted(positional)]
    return plain


def load(path):
    data = open(path, "rb").read()
    if not data.startswith(b"\xff\xfe"):
        sys.exit(f"{path}: must be UTF-16 LE with a BOM")
    return dict(ENTRY.findall(data.decode("utf-16")))


def main():
    tables = {os.path.basename(os.path.dirname(p)): load(p)
              for p in sorted(glob.glob(os.path.join(ROOT, "client", "*.lproj", "Localizable.strings")))}
    english = tables["en.lproj"]
    problems = []
    for language, table in tables.items():
        for key in sorted(set(english) ^ set(table)):
            problems.append(f"{language}: {key} is only in one of en and {language}")
        for key in set(english) & set(table):
            if arguments(english[key]) != arguments(table[key]):
                problems.append(f"{language}: {key}: {table[key]!r} takes {arguments(table[key])}, "
                                f"en {english[key]!r} takes {arguments(english[key])}")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    for problem in problems:
        print(problem)
    print(f"{len(tables)} languages, {len(english)} keys, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
