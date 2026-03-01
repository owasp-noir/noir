+++
title = "HTTP Client Commands"
description = "Generate executable cURL, HTTPie, and PowerShell commands from Noir scan results."
weight = 1
sort_by = "weight"

+++

Generate executable commands for command-line HTTP clients to test discovered endpoints.

## cURL

Generate cURL commands:

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

Generate [HTTPie](https://httpie.io/) commands:

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

Generate PowerShell [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) commands:

```bash
noir -b . -f powershell -u https://www.example.com
```

Example output:
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```
