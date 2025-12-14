+++
title = "HTTP Client Commands"
description = "Learn how to generate executable commands for popular HTTP clients like cURL and HTTPie directly from your Noir scan results. This makes it easy to test and interact with your discovered endpoints."
weight = 1
sort_by = "weight"

[extra]
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
