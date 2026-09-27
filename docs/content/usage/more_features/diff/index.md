+++
title = "Comparing Code with Diff Mode"
description = "Compare two codebase versions to identify endpoint changes."
weight = 2
sort_by = "weight"

+++

Compare two versions of a codebase to identify endpoint changes. Useful for code reviews, security assessments, and understanding feature impacts.

```bash
noir scan <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## Diffing against a git revision

Inside a git repository you don't need a second checkout. `--diff-ref` takes any revision git understands (a branch, tag, commit or `HEAD~1`) and uses it as the old side:

```bash
# What does this branch add to the attack surface compared with main?
noir scan . --diff-ref main

# Only one service in a monorepo
noir scan ./services/billing --diff-ref origin/main -f json
```

Noir writes the files REF tracked under the scanned paths into a temporary directory, scans them as the old side, and deletes the directory when the scan ends. Your HEAD, index and working tree are left alone, and no git hooks run. Code paths of removed endpoints are reported under the path you passed, not the temporary directory.

A few things to keep in mind:

- The new side is the working tree as it is, including untracked files. The old side has only the files git tracked at REF.
- Every base path has to be inside the same repository. `--diff-ref` and `--diff-path` can't be used together.
- A base path that didn't exist at REF is scanned as empty, so everything under it shows up as added.
- CI checkouts are often shallow (`actions/checkout` fetches one commit by default). Fetch the revision first, for example with `fetch-depth: 0`, or Noir stops with an error that says so.

## Output

### Plain Output

The default output groups changes into **Added** (new endpoints), **Removed** (deleted ones), and **Changed** (endpoints present in both versions whose parameters or other details were modified). Endpoints are matched by URL and method, so a method change shows up as one Added plus one Removed. Each section renders endpoints in the standard plain format:

```
───────────── ✚ Added (2) ─────────────

GET /
  ○ headers: 
    └── x-api-key

POST /update

──────────── ✖ Removed (1) ─────────────

GET /secret.html
```

### JSON and YAML Output

Use `-f json` or `-f yaml` for structured output. Results are grouped into three categories.

```json
{
  "added": [...],
  "removed": [...],
  "changed": [...]
}
```

Especially useful in CI/CD: feed only the `added` and `changed` endpoints into a DAST scanner to focus on modified attack surface.
