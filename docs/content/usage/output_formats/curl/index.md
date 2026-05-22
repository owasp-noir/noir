+++
title = "HTTP Client Commands"
description = "Generate executable cURL, HTTPie, and PowerShell commands from Noir scan results."
weight = 1
sort_by = "weight"

+++

Turn discovered endpoints into ready-to-run commands for popular HTTP clients. Use `-u` to set the base URL that gets prepended to each path.

## cURL

[cURL](https://curl.se/) is the most widely used command-line HTTP client. The generated commands include `-i` (show response headers), `-X` (HTTP method), `-d` (request body), `-H` (headers), and `--cookie` as appropriate.

```bash
noir scan . -f curl -u https://www.example.com
```

Example output:
```bash
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
```

## HTTPie

[HTTPie](https://httpie.io/) has a more intuitive syntax than cURL, with colorized output and built-in JSON support.

```bash
noir scan . -f httpie -u https://www.example.com
```

Example output:
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

For Windows environments. Generates [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) commands that work natively without extra tools.

```bash
noir scan . -f powershell -u https://www.example.com
```

Example output:
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```

## Filling Parameter Values

By default Noir leaves parameter values empty (`x-api-key=`, `query=`, …) so the commands work as templates. Pre-populate values with `--pvalue`, handy when you want a script you can run as-is, or when you want to seed fuzzing input.

```
--pvalue TYPE=VALUE     # repeatable
```

| `TYPE`            | Scope                                                |
|-------------------|------------------------------------------------------|
| `any` (or omit)   | Every parameter type                                 |
| `query`           | Query string                                         |
| `form`            | Form body (`application/x-www-form-urlencoded`)      |
| `json`            | JSON body                                            |
| `header`          | Request headers                                      |
| `cookie`          | Cookies                                              |
| `path`            | Path parameters                                      |

`VALUE` accepts two forms:

| Form | Behavior |
|---|---|
| `<value>` | Used for every parameter of the targeted type |
| `<name>=<value>` or `<name>:<value>` | Used only for parameters named `<name>` |

`--pvalue` is repeatable, and per-type rules win over the generic `any` scope when both match.

```bash
# Fill every parameter with `test`
noir scan . -f curl -u https://example.com --pvalue "test"

# Fill only the `Authorization` header and `id` path param
noir scan . -f curl -u https://example.com \
  --pvalue "header=Authorization=Bearer xyz" \
  --pvalue "path=id=42"

# Mix: default `1` for query, but `limit` always 10
noir scan . -f curl -u https://example.com \
  --pvalue "query=1" \
  --pvalue "query=limit=10"
```

The same flag applies to HTTPie and PowerShell output, and feeds downstream into the OpenAPI, Postman, and JSON formats wherever values are rendered.

> **Legacy:** v0's `--set-pvalue`, `--set-pvalue-query`, `--set-pvalue-header`,
> etc. still work as silent aliases in v1.x. New scripts should prefer
> the unified `--pvalue TYPE=VALUE` form above.
