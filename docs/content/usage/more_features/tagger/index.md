+++
title = "Using the Tagger for Contextual Analysis"
description = "Tag endpoints and parameters to point out features and likely security risks."
weight = 3
sort_by = "weight"

+++

Taggers add tags to endpoints and parameters that point out what they do and where the risk may be (SQL injection, login endpoints, and so on).

{% mascot(mood="inspect") %}
Tags are my magnifying glass. A parameter named redirect_url gets flagged as ssrf before anyone reads the handler.
{% end %}

<img src="./tagger.png" alt="Noir output where endpoints carry tags: GET /token is tagged oauth, and GET /api/me is tagged sqli." width="769" height="172" loading="lazy" decoding="async">

## Usage

Taggers are off by default.

**Enable all taggers** (`-T` / `--use-all-taggers`)

```bash
noir scan <BASE_PATH> -T
# equivalent: noir scan <BASE_PATH> --use-all-taggers
```

**Enable specific taggers** (list available ones with `noir list taggers`)

```bash
noir scan <BASE_PATH> --use-taggers hunt,oauth
```

## Output

Tags appear in the `tags` array at both the endpoint level and the parameter level. Each tag has a `name` (short identifier like `sqli` or `oauth`), a human-readable `description`, and the `tagger` that produced it (e.g., `Hunt` for vulnerability patterns, `Oauth` for authentication flows).

```json
{
  "url": "/token",
  "method": "GET",
  "params": [
    {
      "name": "redirect_url",
      "value": "",
      "param_type": "form",
      "tags": [
        {
          "name": "ssrf",
          "description": "This parameter may be vulnerable to Server Side Request Forgery (SSRF) attacks.",
          "tagger": "Hunt"
        }
      ]
    }
  ],
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

Run `noir list taggers` for the current list.

- **Parameter vulnerability classes**: `hunt` tags parameters whose names match known risky patterns (`sqli`, `ssrf`, `idor`, `file-inclusion`, `command-injection`, …).
- **Protocol / interface**: `graphql`, `soap`, `websocket`, `mcp`, `cors`.
- **Authentication & tokens**: `oauth`, `jwt`, plus the framework-aware auth taggers, which tag endpoints that require login with `auth`: `django_auth`, `flask_auth`, `fastapi_auth`, `python_misc_auth`, `spring_auth`, `java_misc_auth`, `ktor_auth`, `scala_auth`, `express_auth`, `nestjs_auth`, `hono_auth`, `js_misc_auth`, `go_auth`, `rust_auth`, `ruby_auth`, `php_auth`, `aspnet_auth`, `fastendpoints_auth`, `elixir_auth`, `swift_auth`, `crystal_auth`, `perl_auth`.
- **Endpoint purpose**: what an endpoint is for, so reviewers can start with the high-stakes ones:
  - `pii`: handles personal data (SSN, card data, contact details). Check for data exposure and over-collection.
  - `admin`: admin or privileged routes (`/admin`, parameters that change privileges). Check for broken access control and privilege escalation.
  - `payment`: payment and financial transaction endpoints. Check for amount/price tampering, currency confusion, and IDOR on financial records.
  - `webhook`: inbound webhook and callback endpoints. Check signature validation, replay protection, and SSRF on outbound calls.
  - `crypto`: endpoints that encrypt, decrypt, sign, hash, or manage keys. Check for weak algorithms, padding/signing oracles, reused IVs or salts, and key exposure.
  - `debug`: debug, diagnostic, and internal-only endpoints (debug consoles/toggles, profilers, actuator/management, pprof, heap/thread dumps, `/internal` APIs). These should not be public. Check for information exposure and unsafe diagnostic actions.
  - `api_docs`: API documentation and schema endpoints (Swagger, OpenAPI, GraphiQL, ReDoc, WSDL). They show the whole API and are often left without auth.
  - `account_recovery`: password reset/change, email change, MFA/OTP, and verification endpoints, where account takeover usually happens. Check for reset-token leaks, host-header injection in reset links, account enumeration, and missing rate limits.
  - `file_upload`: file upload endpoints. Check for unrestricted upload, path traversal, and malicious file handling.
- **Framework protections and risks**: these taggers mark a framework's security controls, and places where code turns off its secure defaults, on the endpoints affected. For Rails (`rails_security`):
  - `csrf-protection`: CSRF verification disabled (`skip_before_action :verify_authenticity_token`, `skip_forgery_protection`) or downgraded (`protect_from_forgery with: :null_session`). Rails protects state-changing requests by default, so check every explicit opt-out.
  - `mass-assignment`: Strong Parameters bypassed (`params.permit!`, `params.to_unsafe_h`, or a raw `params[:x]` hash passed to a model writer such as `Model.new(params[:user])`). Check for attacker-controlled writes to fields like privilege flags or owner columns.
  - `rate-limit`: actions throttled by the Rails 8 native `rate_limit` macro. Its absence on login or recovery routes is itself a finding.

  For Spring (`spring_security`), complementing the `spring_auth` authentication tagger:
  - `csrf-protection`: CSRF turned off in a `SecurityFilterChain`, either wholesale (`csrf().disable()`, `csrf(AbstractHttpConfigurer::disable)`, Kotlin `csrf { disable() }`) or selectively for specific paths (`csrf(c -> c.ignoringRequestMatchers("/api/**"))`). Reported on the affected POST/PUT/PATCH/DELETE endpoints, limited to the chain's `securityMatcher` when there is one. Common for token APIs, but still check it.
  - `cors`: a `@CrossOrigin` annotation on the handler/controller, or a global `WebMvcConfigurer` mapping (`addMapping(...).allowedOrigins("*")`), which relaxes the browser's same-origin rule for the endpoint. Wildcard origins (`*`), especially with credentials, are marked as permissive.
  - `security-headers`: Spring's default response headers weakened: clickjacking protection off (`frameOptions().disable()`) or the whole header writer disabled (`headers().disable()` / `headers(HeadersConfigurer::disable)`).
  - `input-validation`: `@Valid` / `@Validated` applies Bean Validation to the request body. Handlers that take a `@RequestBody` without it stand out by not having the tag.

  For Rust web frameworks (`rust_security`, covering Actix-Web, Axum/tower-http, Rocket, Loco, Warp, …): Rust frameworks turn on no protections by default. The tagger records the ones actually wired up (`.wrap(..)`/`.layer(..)` middleware, or Loco's `config/*.yaml`) and marks risky settings:
  - `cors`: CORS middleware. Permissive configs (`Cors::permissive()`, `CorsLayer::very_permissive()`, `allow_any_origin`, `allow_origins: ["*"]`) are marked as a risk. Restricted allow-lists are recorded as informational.
  - `rate-limit`: request throttling (`actix-governor`, `tower_governor`, `actix-limitation`, tower's limit layers). It is mapped onto the scope it wraps, so you can see which routes have none.
  - `security-headers`: hardening response headers set on the route (HSTS, CSP, `X-Frame-Options`, `X-Content-Type-Options`, …).
  - `body-limit`: request body size cap (DoS mitigation). A disabled limit (`DefaultBodyLimit::disable()`) is marked as a risk.

  For Go web frameworks (`go_security`), the tagger maps protective middleware onto each endpoint. Go turns none of it on by default, so whether it is there (or missing on a state-changing route) is the signal. It reads group-level `.Use(...)`, global wrappers, and inline route middleware in Echo, Gin, Fiber, Chi and others:
  - `csrf-protection`: CSRF middleware on the route (`middleware.CSRF` for Echo, `csrf.New` for Fiber, `csrf.Protect` for gorilla/csrf, gin-csrf, `nosurf`). Check cookie-authenticated state-changing routes that lack it.
  - `security-headers`: response-hardening middleware (Echo `middleware.Secure`, Fiber `helmet`, unrolled/gin-contrib `secure`) that sets HSTS / `X-Frame-Options` / nosniff / XSS protections.
  - `rate-limit`: throttling middleware (Echo `RateLimiter`, chi `Throttle`, Fiber/ulule `limiter`, go-chi/httprate, tollbooth). Shows which routes are open to brute force or abuse.
  - `body-limit`: request body size cap (Echo `BodyLimit`, gin-contrib/size), a DoS guard.
  - `timeout`: request-timeout middleware (Echo/chi `middleware.Timeout`, Fiber `timeout`), a guard against slow requests.
  - `cors`: CORS middleware (Echo `middleware.CORS`, Fiber/gin-contrib/go-chi/rs `cors`, gorilla `handlers.CORS`). Known permissive constructors (`cors.Default()`, `cors.AllowAll()`) are marked as allowing all origins. This adds to the `cors` tagger, which looks at header params.
  - `secure-cookies`: cookie confidentiality/integrity middleware (Fiber `encryptcookie`).

Endpoint tags also go into the AI context as signals, so they show up in the per-endpoint summary an AI reviewer reads.
