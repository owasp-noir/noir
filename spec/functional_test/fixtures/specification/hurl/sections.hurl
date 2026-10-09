# Request sections, a templated host and a response half whose
# captures/asserts must not leak into the request.
GET {{host}}/search
[QueryStringParams]
q: noir
page: 1
[Cookies]
session: abc
HTTP 200
[Captures]
next_url: jsonpath "$.next"
[Asserts]
header "Content-Type" contains "json"

POST {{host}}/upload
[Form]
title: report
[BasicAuth]
bob: secret
HTTP *

PATCH https://example.org/api/items/{{item_id}}
X-Api-Key: k1
{
  "name": "widget",
  "count": {{count}}
}
HTTP 204

POST https://example.org/api/notes
```
GET this is not a request
```
HTTP 201
