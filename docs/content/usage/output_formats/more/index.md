+++
title = "Additional Output Formats"
description = "Specialized output formats like only-url, only-param, markdown-table, and Postman collections."
weight = 6
sort_by = "weight"

+++

## Filtering with `only-*` Formats

Extract a single type of data from scan results.

### URLs Only

```bash
noir -b . -f only-url
```

```
/
/query
/token
/socket
/1.html
/2.html
```

### Parameters Only

```bash
noir -b . -f only-param
```

```
query
client_id
redirect_url
grant_type
```

### Headers Only

```bash
noir -b . -f only-header
```

```
x-api-key
Cookie
```

### Cookies Only

```bash
noir -b . -f only-cookie
```

```
my_auth
```

### Tags Only

```bash
noir -b . -f only-tag -T
```

```
sqli
oauth
websocket
```

## Markdown Table

```bash
noir -b . -f markdown-table
```

| Endpoint    | Protocol | Params                                                              |
|-------------|----------|---------------------------------------------------------------------|
| GET /       | http     | `x-api-key (header)`                                                |
| POST /query | http     | `my_auth (cookie)` `query (form)`                                   |
| GET /token  | http     | `client_id (form)` `redirect_url (form)` `grant_type (form)`        |
| GET /socket | ws       |                                                                     |
| GET /1.html | http     |                                                                     |
| GET /2.html | http     |                                                                     |

## JSON Lines (JSONL)

```bash
noir -b . -f jsonl
```

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","type":"header","value":""}]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","type":"cookie","value":""},{"name":"query","type":"form","value":""}]}
{"url":"/token","method":"GET","params":[{"name":"client_id","type":"form","value":""}]}
```

Useful for streaming large result sets and line-by-line processing.

## Postman Collection

```bash
noir -b . -f postman -u https://api.example.com
```

Generates a Postman Collection v2.1 JSON file. Save the output and import it into Postman for interactive API testing.

```json
{
  "info": {
    "name": "Noir Scan Results",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "GET /",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "x-api-key",
            "value": ""
          }
        ],
        "url": "https://api.example.com/"
      }
    }
  ]
}
```
