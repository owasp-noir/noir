+++
title = "HTTP Client Command Generation"
description = "Learn how to generate executable commands for popular HTTP clients like cURL and HTTPie directly from your Noir scan results. This makes it easy to test and interact with your discovered endpoints."
weight = 1
sort_by = "weight"

[extra]
+++

Noir can automatically generate commands for your favorite command-line HTTP clients, making it incredibly easy to start testing and interacting with the endpoints you discover. This feature is a great way to bridge the gap between code analysis and hands-on testing.

## cURL

To generate a list of `curl` commands for your endpoints, use the `-f curl` or `--format curl` flag. You'll also need to provide a base URL with the `-u` flag so that Noir can construct the full request URLs.

```bash
noir -b . -f curl -u https://www.example.com
```

This will output a series of `curl` commands, one for each endpoint, complete with the correct HTTP method, headers, and parameters.

```bash
# Example Output
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
# ... and so on
```

## HTTPie

If you prefer to use [HTTPie](https://httpie.io/), Noir can generate commands for it as well. Use the `-f httpie` flag, and again, provide a base URL.

```bash
noir -b . -f httpie -u https://www.example.com
```

This will produce a list of `http` commands that you can run directly in your terminal.

```bash
# Example Output
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
# ... and so on
```

By using this feature, you can quickly and easily start testing your endpoints without having to manually construct each request.
