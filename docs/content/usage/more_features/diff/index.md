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

## Output

### Plain Output

The default output groups changes into **Added** (new endpoints), **Removed** (deleted ones), and **Changed** (endpoints present in both versions whose parameters or other details were modified — endpoints are matched by URL and method, so a method change shows up as one Added plus one Removed). Each section renders endpoints in the standard plain format:

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
