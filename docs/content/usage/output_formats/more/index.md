+++
title = "Additional Output Formats"
description = "Noir provides a variety of additional output formats to help you extract specific information from your codebase. This page details how to use formats like 'only-url', 'only-param', and 'markdown-table' to customize the output to your needs."
weight = 5
sort_by = "weight"

[extra]
+++

Noir supports a range of specialized output formats for when you need to isolate specific pieces of information. These formats are designed to give you quick access to the data you need without any extra noise. Below are some of the most useful additional formats available.

## Filtering for Specific Information

You can use the `only-*` formats to extract just one type of data from the scan.

### URLs Only

To get a list of all discovered URLs, use the `only-url` format:

```bash
noir -b . -f only-url
```

This will output a simple list of endpoints:

```
/
/query
/token
/socket
/1.html
/2.html
```

### Parameters Only

To extract all unique parameter names, use `only-param`:

```bash
noir -b . -f only-param
```

This will list all parameter names found in the codebase:

```
query
client_id
redirect_url
grant_type
```

### Headers Only

To get a list of all HTTP headers, use `only-header`:

```bash
noir -b . -f only-header
```

This will output the names of the headers:

```
x-api-key
Cookie
```

### Cookies Only

To list all cookie names, use `only-cookie`:

```bash
noir -b . -f only-cookie
```

This will show just the names of the cookies:

```
my_auth
```

### Tags Only

If you've applied tags to your endpoints, you can list them with `only-tag`:

```bash
noir -b . -f only-tag -T
```

This will output all unique tags:

```
sqli
oauth
websocket
```

## Markdown Table Format

For a clean, human-readable table of all endpoints and their parameters, use the `markdown-table` format:

```bash
noir -b . -f markdown-table
```

This generates a Markdown table that you can easily copy into documentation or reports:

| Endpoint    | Protocol | Params                                                              |
|-------------|----------|---------------------------------------------------------------------|
| GET /       | http     | `x-api-key (header)`                                                |
| POST /query | http     | `my_auth (cookie)` `query (form)`                                   |
| GET /token  | http     | `client_id (form)` `redirect_url (form)` `grant_type (form)`        |
| GET /socket | ws       |                                                                     |
| GET /1.html | http     |                                                                     |
| GET /2.html | http     |                                                                     |

