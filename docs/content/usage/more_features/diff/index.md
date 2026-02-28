+++
title = "Comparing Code with Diff Mode"
description = "Compare two codebase versions to identify endpoint changes."
weight = 2
sort_by = "weight"

+++

Compare two versions of a codebase to identify endpoint changes. Useful for code reviews, security assessments, and understanding feature impacts.

Usage:

```bash
noir -b <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## Output

### Plain Output

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
```

### JSON and YAML Output

Use `-f json` or `-f yaml` for structured output:

```json
{
  "added": [...],
  "removed": [...],
  "changed": [...]
}
```

Use diff mode in CI/CD to configure DAST tools to scan only modified endpoints.
