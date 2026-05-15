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
noir -b . -f curl -u https://www.example.com
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
noir -b . -f httpie -u https://www.example.com
```

Example output:
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

For Windows environments — generates [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) commands that work natively without extra tools.

```bash
noir -b . -f powershell -u https://www.example.com
```

Example output:
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```

## Filling Parameter Values

By default Noir leaves parameter values empty (`x-api-key=`, `query=`, …) so the commands work as templates. Pre-populate values with the `--set-pvalue` family — handy when you want a script you can run as-is, or when you want to seed fuzzing input.

| Flag | Scope |
|---|---|
| `--set-pvalue VALUE` | All parameter types |
| `--set-pvalue-query VALUE` | Query string |
| `--set-pvalue-form VALUE` | Form body (`application/x-www-form-urlencoded`) |
| `--set-pvalue-json VALUE` | JSON body |
| `--set-pvalue-header VALUE` | Request headers |
| `--set-pvalue-cookie VALUE` | Cookies |
| `--set-pvalue-path VALUE` | Path parameters |

`VALUE` accepts two forms:

| Form | Behavior |
|---|---|
| `<value>` | Used for every parameter of the targeted type |
| `<name>=<value>` or `<name>:<value>` | Used only for parameters named `<name>` |

All flags are repeatable, and per-type rules win over the generic `--set-pvalue` when both match.

```bash
# Fill every parameter with `test`
noir -b . -f curl -u https://example.com --set-pvalue "test"

# Fill only the `Authorization` header and `id` path param
noir -b . -f curl -u https://example.com \
  --set-pvalue-header "Authorization=Bearer xyz" \
  --set-pvalue-path "id=42"

# Mix: default `1` for query/form, but `limit` always 10
noir -b . -f curl -u https://example.com \
  --set-pvalue-query "1" \
  --set-pvalue-query "limit=10"
```

The same flags apply to HTTPie and PowerShell output, and feed downstream into the OpenAPI, Postman, and JSON formats wherever values are rendered.
