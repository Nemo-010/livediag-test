#!/usr/bin/env python3
"""Validate a livediag results.tsv against a small expectation file.

Expectation language (one rule per line, # for comments):

  require ID STATUS              status must be exactly STATUS
  oneof ID S1 S2 ...             status must be one of the listed ones
  contains ID TEXT               the message must contain TEXT (case folded)
  not-contains ID TEXT           the message must not contain TEXT
  forbid ID                      the module must not appear at all
  no-status STATUS               no module may have this status
  min-results N                  at least N modules must have reported

Every results file is additionally checked for unknown statuses and
duplicate module ids.
"""

import argparse
import os
import sys

KNOWN = {"PASS", "FAIL", "WARN", "SKIP", "TIMEOUT", "INFO"}


def load_results(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 5:
                raise SystemExit(f"{path}:{lineno}: malformed line: {line!r}")
            rows.append({
                "ts": parts[0],
                "id": parts[1],
                "status": parts[2],
                "name": parts[3],
                "message": parts[4],
                "category": parts[5] if len(parts) > 5 else "Other",
            })
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("expect")
    parser.add_argument("results")
    parser.add_argument("--summary", default=None,
                        help="append a markdown summary to this file")
    args = parser.parse_args()

    rows = load_results(args.results)
    by_id = {}
    errors = []

    for row in rows:
        if row["status"] not in KNOWN:
            errors.append(f"{row['id']}: unknown status {row['status']!r}")
        if row["id"] in by_id:
            errors.append(f"{row['id']}: duplicate result")
        by_id[row["id"]] = row

    with open(args.expect, encoding="utf-8") as handle:
        rules = [line.strip() for line in handle
                 if line.strip() and not line.lstrip().startswith("#")]

    for rule in rules:
        parts = rule.split()
        op = parts[0].lower()
        if op == "require" and len(parts) >= 3:
            row = by_id.get(parts[1])
            if row is None:
                errors.append(f"missing module {parts[1]}")
            elif row["status"] != parts[2]:
                errors.append(
                    f"{parts[1]}: expected {parts[2]}, got {row['status']}")
        elif op == "oneof" and len(parts) >= 3:
            row = by_id.get(parts[1])
            if row is None:
                errors.append(f"missing module {parts[1]}")
            elif row["status"] not in parts[2:]:
                errors.append(
                    f"{parts[1]}: expected one of {parts[2:]}, got {row['status']}")
        elif op in ("contains", "not-contains") and len(parts) >= 3:
            row = by_id.get(parts[1])
            needle = " ".join(parts[2:]).lower()
            if row is None:
                errors.append(f"missing module {parts[1]}")
            else:
                present = needle in row["message"].lower()
                if op == "contains" and not present:
                    errors.append(
                        f"{parts[1]}: message lacks {needle!r}")
                if op == "not-contains" and present:
                    errors.append(
                        f"{parts[1]}: message unexpectedly has {needle!r}")
        elif op == "forbid" and len(parts) >= 2:
            if parts[1] in by_id:
                errors.append(f"module {parts[1]} should not have run")
        elif op == "no-status" and len(parts) >= 2:
            offenders = [r["id"] for r in rows if r["status"] == parts[1]]
            if offenders:
                errors.append(
                    f"status {parts[1]} forbidden but present for: "
                    + ", ".join(offenders))
        elif op == "min-results" and len(parts) >= 2:
            if len(rows) < int(parts[1]):
                errors.append(
                    f"expected at least {parts[1]} results, got {len(rows)}")
        else:
            errors.append(f"unknown expectation: {rule}")

    print(f"results: {len(rows)} module(s)")
    for row in rows:
        print(f"  {row['status']:<8} {row['id']:<22} {row['message']}")

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as out:
            out.write("| status | module | detail |\n")
            out.write("| --- | --- | --- |\n")
            for row in rows:
                out.write(
                    f"| {row['status']} | `{row['id']}` | {row['message']} |\n")

    if errors:
        print("\nFAILED expectations:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("\nall expectations satisfied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
