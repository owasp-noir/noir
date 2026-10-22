# api.hurl
GET https://example.org/api/health
HTTP 200

POST https://example.org/api/login
Content-Type: application/json
{"user": "bob", "password": "x"}

PUT https://example.org/api/users/42?force=true
Authorization: Bearer {{token}}
