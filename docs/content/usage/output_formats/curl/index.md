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
