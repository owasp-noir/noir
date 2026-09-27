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

The default output groups changes into **Added** (new endpoints), **Removed** (deleted ones), and **Changed** (endpoints present in both versions whose parameters or tags differ). Endpoints are matched by URL and method, so a method change shows up as one Added plus one Removed. Each section renders endpoints in the standard plain format, and every Changed endpoint is followed by what changed:

```
───────────── ✚ Added (2) ─────────────

GET /
  ○ headers: 
    └── x-api-key

POST /update

──────────── ✖ Removed (1) ─────────────

GET /secret.html

──────────── ≠ Changed (2) ─────────────

GET /public?q=
  + query: q

GET /profile
  ! auth tag removed
```

### What counts as changed

- **Params** are compared by name and where they are sent (query, header, cookie, path, form, JSON body). A param that only changed its example or default value is not a change, since a client sends nothing different.
- **Tags** are compared by name. Tags come from taggers, so run the diff with `-T` (or `--use-taggers`) to see them.
- **`auth` removed**: when an endpoint had the `auth` tag before and doesn't now, the report puts `! auth tag removed` first. This is the change to look at hardest in a review: a route that used to require login and no longer does. The auth taggers only run with `-T` or `--use-taggers`, so enable one of them to get this line.

### JSON and YAML Output

Use `-f json` or `-f yaml` for structured output. Results are grouped into three categories.

```json
{
  "added": [...],
  "removed": [...],
  "changed": [...],
  "changes": [
    {
      "method": "GET",
      "url": "/profile",
      "params_added": [],
      "params_removed": [{ "name": "token", "param_type": "header" }],
      "tags_added": [],
      "tags_removed": ["auth"],
      "auth_removed": true
    }
  ]
}
```

`changed` holds the endpoints as they are now. `changes` has one record per entry in `changed`, in the same order, saying what differs.

Especially useful in CI/CD: feed only the `added` and `changed` endpoints into a DAST scanner to focus on modified attack surface.
