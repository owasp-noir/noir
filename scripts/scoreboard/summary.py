"""Write the scheduled run's comparison to stdout and fail on regressions."""

import json
import sys
from html import escape
from pathlib import Path


def repositories(path):
    rows = json.loads(Path(path).read_text())["repositories"]
    return {(row["name"], row["technology"]): row for row in rows}


def counts(row):
    if row is None:
        return "—"
    return " / ".join(str(row[key]) for key in ("matched", "spec_only", "code_only"))


def summary(before, after, artifacts):
    failed = False
    print("### Route counts\n")
    print("Repository | Technology | Current matched / document-only / code-only | Committed matched / document-only / code-only")
    print("--- | --- | ---: | ---:")
    for key in sorted(before.keys() | after.keys()):
        old, new = before.get(key), after.get(key)
        regression = old is not None and (
            new is None or new["matched"] < old["matched"] or new["spec_only"] > old["spec_only"]
        )
        failed |= regression
        status = " **regression**" if regression else ""
        print(f"{key[0]} | {key[1]} | {counts(new)}{status} | {counts(old)}")

    print("\n### Sampled rows without a label\n")
    missing = 0
    for tech in sorted({tech for _, tech in after}):
        rows = json.loads((artifacts / f"{tech}-audit-sample.json").read_text())
        for row in rows:
            if row["verdict"] is None:
                identity = " ".join(row[k] for k in ("repository", "side", "method", "url"))
                print(f"- <code>{escape(tech)} {escape(identity)}</code>")
                missing += 1
    print(f"\n{missing} unlabelled sampled rows.")
    return int(failed)


if __name__ == "__main__":
    sys.exit(summary(repositories(sys.argv[1]), repositories(sys.argv[2]), Path(sys.argv[3])))
