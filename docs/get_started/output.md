---
title: Output Handling
parent: Get Started
has_children: false
nav_order: 3
layout: page
---

```bash
noir -b <BASE_PATH> -f <FORMAT>

# You can check the format list with the -h flag.
#     -f FORMAT, --format json         Set output format
#                                       * plain yaml json jsonl markdown-table
#                                       * curl httpie oas2 oas3
#                                       * only-url only-param only-header only-cookie

```

## JSON
```bash
noir -b . -f json --no-log
```

```json
{
    "url": "https://testapp.internal.domains/query",
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
          "path": "spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
          "line": 8
        }
      ]
    },
    "protocol": "http",
    "tags": []
}
```

## YAML
```bash
noir -b . -f yaml --no-log
```

```yaml
- url: /
  method: GET
  params:
  - name: x-api-key
    value: ""
    param_type: header
    tags: []
  details:
    code_paths:
    - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
      line: 3
  protocol: http
  tags: []
- url: /query
  method: POST
  params:
  - name: my_auth
    value: ""
    param_type: cookie
    tags: []
  - name: query
    value: ""
    param_type: form
    tags: []
  details:
    code_paths:
    - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
      line: 8
  protocol: http
  tags: []
# .......
```

## Friendly tools

### curl
```bash
noir -b . -f curl -u https://www.hahwul.com

# curl -i -X GET https://www.hahwul.com/ -H "x-api-key: "
# curl -i -X POST https://www.hahwul.com/query -d "query=" --cookie "my_auth="
# curl -i -X GET https://www.hahwul.com/token -d "client_id=&redirect_url=&grant_type="
# curl -i -X GET https://www.hahwul.com/socket
# curl -i -X GET https://www.hahwul.com/1.html
# curl -i -X GET https://www.hahwul.com/2.html
```

### httpie

```bash
noir -b . -f httpie -u https://www.hahwul.com

# http GET https://www.hahwul.com/ "x-api-key: "
# http POST https://www.hahwul.com/query "query=" "Cookie: my_auth="
# http GET https://www.hahwul.com/token "client_id=&redirect_url=&grant_type="
# http GET https://www.hahwul.com/socket
# http GET https://www.hahwul.com/1.html
# http GET https://www.hahwul.com/2.html
```

### Only-x
```bash
noir -b . -f only-url
# ...
# /
# /query
# /token
# /socket
# /1.html
# /2.html
```