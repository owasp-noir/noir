---
title: Use Tagger
has_children: false
nav_order: 3
layout: page
---

# Tagger
{: .d-inline-block }

Since (v0.14.0) 
{: .label .label-green }

The Tagger is a feature that adds tags to Endpoints, Params, etc., based on given conditions or logic when Noir analyzes source code. By using this feature, you can attach tag information that matches the characteristics of the Endpoints and Params. This helps analysts easily understand Endpoints or gain hints for the next security testing.

![](../../images/advanced/tagger.png)

## Activation and Usage of Tagger
The Tagger is disabled by default. You can enable the entire Tagger using the `-T` or `--use-all-taggers` flag or specify desired Taggers with the `--use-taggers` option. The list of available Taggers can be found using the `--list-taggers` option.

```bash
noir -b <BASE_PATH> -T

# You can check the format list with the -h flag.
#   TAGGER:
#     -T, --use-all-taggers            Activates all taggers for full analysis coverage
#     --use-taggers VALUES             Activates specific taggers (e.g., --use-taggers hunt,oauth)
#     --list-taggers                   Lists all available taggers
```

## Output Format with Tagger
When using the Tagger, tags will be displayed along with the results in Plain output as shown below. In JSON or YAML results, separate Tagger information will be included for Endpoints and Params.

```bash
noir -b <BASE_PATH> -T -f json
```

```json
{
    "url": "/query",
    "method": "POST",
    "params": [
      {
        "name": "my_auth",
        "value": "",
        "param_type": "cookie",
        "tags": []
      },
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
    "details": {
      "code_paths": [
        {
          "path": "./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
          "line": 8
        }
      ]
    },
    "protocol": "http",
    "tags": []
  },
  {
    "url": "/token",
    "method": "GET",
    "params": [
      {
        "name": "client_id",
        "value": "",
        "param_type": "form",
        "tags": []
      },
      {
        "name": "redirect_url",
        "value": "",
        "param_type": "form",
        "tags": []
      },
      {
        "name": "grant_type",
        "value": "",
        "param_type": "form",
        "tags": []
      }
    ],
    "details": {
      "code_paths": [
        {
          "path": "./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
          "line": 13
        }
      ]
    },
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