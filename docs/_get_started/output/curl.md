---
title: CURL
parent: Output Formatting
has_children: false
nav_order: 3
layout: page
---

```bash
noir -b . -f curl -u https://www.hahwul.com

# curl -i -X GET https://www.hahwul.com/ -H "x-api-key: "
# curl -i -X POST https://www.hahwul.com/query -d "query=" --cookie "my_auth="
# curl -i -X GET https://www.hahwul.com/token -d "client_id=&redirect_url=&grant_type="
# curl -i -X GET https://www.hahwul.com/socket
# curl -i -X GET https://www.hahwul.com/1.html
# curl -i -X GET https://www.hahwul.com/2.html
```