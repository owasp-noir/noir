+++
title = "Using the Tagger for Contextual Analysis"
description = "Automatically tag endpoints and parameters to identify potential security risks."
weight = 3
sort_by = "weight"

+++

Automatically add descriptive tags to endpoints and parameters to identify functionality and potential security risks (e.g., SQL injection, authentication endpoints).

![](./tagger.png)

## Usage

Tagger is disabled by default. Enable it:

**Enable all taggers**:

```bash
noir -b <BASE_PATH> -T
```

**Enable specific taggers** (list available with `noir --list-taggers`):

```bash
noir -b <BASE_PATH> --use-taggers hunt,oauth
```

## Output

Tags are added to the `tags` array for each endpoint and parameter:

```json
{
  "url": "/query",
  "method": "POST",
  "params": [
    {
      "name": "query",
      "value": "",
      "param_type": "form",
      "tags": [
        {
          "name": "sqli",
          "description": "This parameter may be vulnerable to SQL Injection attacks.",
          "tagger": "Hunt"
        }
      ]
    }
  ],
  "protocol": "http",
  "tags": []
},
{
  "url": "/token",
  "method": "GET",
  "protocol": "http",
  "tags": [
    {
      "name": "oauth",
      "description": "Suspected OAuth endpoint for granting 3rd party access.",
      "tagger": "Oauth"
    }
  ]
}
```
