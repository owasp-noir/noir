+++
title = "Comparing Code with Diff Mode"
description = "Learn how to use Noir's diff mode to compare two different versions of a codebase and identify what has changed. This is a powerful feature for understanding the impact of code changes on your API."
weight = 2
sort_by = "weight"

[extra]
+++

Diff mode is a powerful feature in Noir that allows you to compare two versions of a codebase and see exactly what has changed in terms of the discovered endpoints. This can be incredibly useful for code reviews, security assessments, and for understanding the impact of a new feature.

To use diff mode, you provide a base path with the `-b` flag (representing the new version of the code) and a comparison path with the `--diff-path` flag (representing the old version).

```bash
noir -b <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## Understanding the Output

The output of the diff mode will show you which endpoints have been added, removed, or changed between the two versions.

### Plain Output

In the default plain text output, you will get a simple summary of the changes:

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
```

### JSON and YAML Output

For a more detailed and machine-readable output, you can use the JSON or YAML formats (`-f json` or `-f yaml`). This will provide a structured view of the added, removed, and changed endpoints, including their full details.

```json
{
  "added": [
    {
      "url": "/",
      "method": "GET",
      // ... full endpoint details
    }
  ],
  "removed": [
    {
      "url": "/secret.html",
      "method": "GET",
      // ... full endpoint details
    }
  ],
  "changed": []
}
```

By using diff mode, you can build more efficient CI/CD pipelines. For example, you could configure a DAST (Dynamic Application Security Testing) tool to only scan the endpoints that have been added or modified in a new release, saving time and resources.
