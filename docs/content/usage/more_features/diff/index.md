+++
title = "Comparing Code with Diff Mode"
description = "Compare two codebase versions to identify endpoint changes."
weight = 2
sort_by = "weight"

+++

Compare two versions of a codebase to identify endpoint changes. Useful for code reviews, security assessments, and understanding feature impacts.

```bash
noir -b <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## Output

### Plain Output

The default output marks each change as **Added** (new endpoints), **Removed** (deleted ones), or **Changed** (endpoints whose parameters or methods were modified).

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
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

Especially useful in CI/CD — feed only the `added` and `changed` endpoints into a DAST scanner to focus on modified attack surface.
