---
title: More
parent: Output Formatting
has_children: false
nav_order: 4
layout: page
---

# More formats

Noir supports additional output formats for specific use cases. Below are some of the formats you can use.

## Only X
### URL
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

### Param
```bash
noir -b . -f only-param
# ...
# query
# client_id
# redirect_url
# grant_type
```

### Header
```bash
noir -b . -f only-header
# ...
# x-api-key
# Cookie
```

### Cookie
```bash
noir -b . -f only-cookie
# ...
# my_auth
```

### Tag

```bash
noir -b . -f only-tag -T
# ...
# sqli
# oauth
# websocket
```

## Markdown

```bash
noir -b . -f markdown-table
```

```markdown
| Endpoint | Protocol | Params |
| -------- | -------- | ------ |
| GET / | http | `x-api-key (header)`  |
| POST /query | http | `my_auth (cookie)` `query (form)`  |
| GET /token | http | `client_id (form)` `redirect_url (form)` `grant_type (form)`  |
| GET /socket | ws |  |
| GET /1.html | http |  |
| GET /2.html | http |  |
```

| Endpoint | Protocol | Params |
| -------- | -------- | ------ |
| GET / | http | `x-api-key (header)`  |
| POST /query | http | `my_auth (cookie)` `query (form)`  |
| GET /token | http | `client_id (form)` `redirect_url (form)` `grant_type (form)`  |
| GET /socket | ws |  |
| GET /1.html | http |  |
| GET /2.html | http |  |