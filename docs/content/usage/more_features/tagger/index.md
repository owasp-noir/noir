+++
title = "Using the Tagger for Contextual Analysis"
description = "Automatically tag endpoints and parameters to identify potential security risks."
weight = 3
sort_by = "weight"

+++

Automatically add descriptive tags to endpoints and parameters to flag functionality and potential security risks (e.g., SQL injection, authentication endpoints).

![](./tagger.png)

## Usage

Tagger is disabled by default.

**Enable all taggers**

```bash
noir scan <BASE_PATH> -T
```

**Enable specific taggers** (list available ones with `noir list taggers`)

```bash
noir scan <BASE_PATH> --use-taggers hunt,oauth
```

## Output

Tags appear in the `tags` array at both the endpoint level and the parameter level. Each tag has a `name` (short identifier like `sqli` or `oauth`), a human-readable `description`, and the `tagger` that produced it (e.g., `Hunt` for vulnerability patterns, `Oauth` for authentication flows).

```json
{
  "url": "/query",
  "method": "POST",
  "params": [
    {
      "name": "query",
      "value": "",
      "param_type": "form",
      "tags": [
        {
          "name": "sqli",
          "description": "This parameter may be vulnerable to SQL Injection attacks.",
          "tagger": "Hunt"
        }
      ]
    }
  ],
  "protocol": "http",
  "tags": []
},
{
  "url": "/token",
  "method": "GET",
  "protocol": "http",
  "tags": [
    {
      "name": "oauth",
      "description": "Suspected OAuth endpoint for granting 3rd party access.",
      "tagger": "Oauth"
    }
  ]
}
```

## Tag categories

Taggers span several kinds of security-relevant signal. Run `noir list taggers` for the full, up-to-date list.

- **Parameter vulnerability classes** — `hunt` flags individual parameters that match known-risky names (`sqli`, `ssrf`, `idor`, `file-inclusion`, `command-injection`, …).
- **Protocol / interface** — `graphql`, `soap`, `websocket`, `mcp`, `cors`.
- **Authentication & tokens** — `oauth`, `jwt`, plus the framework-aware auth taggers (Spring Security, Django, Express, …).
- **Endpoint sensitivity & purpose** — classify *what an endpoint is for* so reviewers can prioritize the highest-stakes surface:
  - `pii` — handles personally identifiable information (SSN, card data, contact details); review for data exposure and over-collection.
  - `admin` — administrative or privileged routes (`/admin`, privilege-mutating parameters); prime targets for broken access control and privilege escalation.
  - `payment` — payment / financial transaction endpoints; review for amount/price tampering, currency confusion, and IDOR on financial records.
  - `webhook` — inbound webhook / callback endpoints; verify signature validation, replay protection, and SSRF on outbound calls.
  - `crypto` — cryptographic operation endpoints (encryption/decryption, signing, hashing, key management); review for weak or obsolete algorithms, padding/signing oracles, static IV/salt reuse, and key exposure.
  - `file_upload` — file upload endpoints; review for unrestricted upload, path traversal, and malicious file handling.

Endpoint-level tags also feed the AI context as signals, enriching the per-endpoint summary that AI reviewers consume.
