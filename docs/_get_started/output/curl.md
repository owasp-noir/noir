---
title: Curl and HTTPie
parent: Output Formatting
has_children: false
nav_order: 4
layout: page
---

## Curl

```bash
noir -b . -f curl -u https://www.hahwul.com

# curl -i -X GET https://www.hahwul.com/ -H "x-api-key: "
# curl -i -X POST https://www.hahwul.com/query -d "query=" --cookie "my_auth="
# curl -i -X GET https://www.hahwul.com/token -d "client_id=&redirect_url=&grant_type="
# curl -i -X GET https://www.hahwul.com/socket
# curl -i -X GET https://www.hahwul.com/1.html
# curl -i -X GET https://www.hahwul.com/2.html
```

## HTTPie

```bash
noir -b . -f httpie -u https://www.hahwul.com

# http GET https://www.hahwul.com/ "x-api-key: "
# http POST https://www.hahwul.com/query "query=" "Cookie: my_auth="
# http GET https://www.hahwul.com/token "client_id=&redirect_url=&grant_type="
# http GET https://www.hahwul.com/socket
# http GET https://www.hahwul.com/1.html
# http GET https://www.hahwul.com/2.html
```