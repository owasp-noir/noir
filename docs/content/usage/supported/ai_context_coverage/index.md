+++
title = "AI Context"
description = "Per-endpoint AI review context that aggregates guards, callees, sources, sinks, validators, and signals."
weight = 5
sort_by = "weight"

+++

Noir can attach a structured AI review context to each endpoint. It collects the static signals that LLM-based SAST tools, code reviewers, and security agents need to triage a route, so they don't have to walk the repository themselves.

Use `--ai-context` to enable it:

```bash
noir scan . --ai-context
```

Pass a comma-separated list of buckets to keep only the categories you need. The filter runs on the data itself, so JSON, SARIF, YAML, Postman, and OAS output get the same selection as plain text.

```bash
noir scan . --ai-context=guards,sinks       # auth + sinks, plus linked signals
noir scan . --ai-context=callee             # only the 1-hop handler callees
noir scan . --ai-context=all                # explicit form of "everything"
noir scan . --ai-context                    # bare form: also "everything"
```

Valid feature names: `guards`, `callee`, `sources`, `sinks`, `validators`, `signals` (plus `all`). Names are case-insensitive.

Signals are derived from the other buckets, and the filter keeps them
together. Selecting `signals` keeps the evidence those signals need (for
example `ssrf` keeps `outbound_http` sinks). Selecting an evidence bucket
keeps only the signals linked to it (for example `guards,sinks` still
shows `authz_absence`), and each of those signals brings its own evidence
along, so `guards,sinks` can also show `sources`. The `priority_review` roll-up, which draws on
several buckets, appears only when `signals` is selected (bare
`--ai-context` and `all` include it).

In plain output, every endpoint with non-empty context gets an `ai_context:` block. Structured formats put the same data here:

| Format | Where AI context appears |
|---|---|
| JSON / JSONL / YAML / TOML | `endpoints[].ai_context` |
| OpenAPI 2.0 / 3.0 | Operation-level `x-noir-ai-context` extension |
| SARIF | `result.properties.noir.ai_context` |
| Postman | Appended to the item description |
| cURL / HTTPie / PowerShell / only-url / only-param | Left out on purpose, so their main output stays the same |

## What goes inside

Every context bucket is a list of entries with `kind`, `name`, optional `source`, `description`, `path`, `line`, `confidence`, and `snippet`. The buckets are:

| Bucket | Meaning |
|---|---|
| `guards` | Authentication / authorization gates detected on the route (middleware, decorators, `requires_auth`, role checks, etc.) |
| `callees` | The 1-hop handler callees Noir already collects with `--include callee`, repeated inside the AI context so everything is in one place |
| `sources` | Attacker-controlled inputs that reach the handler: each request parameter, header, cookie, and GraphQL field, plus mobile deep-link payloads. A few server-side value sources worth reviewing (a Spring `@Value` secret, a WebSocket CORS policy) land here too |
| `sinks` | Likely dangerous operations inferred from the handler body or callee names (SQL, command execution, deserialization, template rendering, file I/O, redirects, etc.) |
| `validators` | Input-validation and sanitization signals (schema validators, parameter coercion, allow-listing patterns) that mitigate sink risk |
| `signals` | Other route-shape hints worth surfacing (state-changing methods without a detected guard, path-id usage suggesting object-level authorization concerns, file-upload behavior, etc.) |

The kinds each bucket can hold are listed under [Kinds by bucket](#kinds-by-bucket).

The list is best-effort. Heuristic confidence is exposed on each entry so consumers can filter by threshold. Each bucket keeps at most 16 entries so the output stays compact.

Every non-empty context also carries `"untrusted_fields": ["name", "path", "snippet"]`. Those fields come from the scanned repository as-is, so `snippet` includes comments and string literals written by whoever controls that code. When you pass this output to an LLM, treat those fields as untrusted data and fence them off from your instructions.

The shape is published as a JSON Schema at [`schemas/ai-context.schema.json`](https://owasp-noir.github.io/noir/schemas/ai-context.schema.json), for validators and for prompts that need a stable contract. The untrusted fields carry `"x-noir-untrusted": true` there. Entry `kind` values are an open vocabulary: new ones are added without a schema change.

## Reading an entry

Here is one endpoint from a Phoenix app, narrowed to two buckets with `--ai-context=guards,sinks`. The later snippets are cut short here:

```text
DELETE /settings/keys/:id
  ○ path: id
  ○ tags: idor auth
  ○ ai_context:
    - guards:
      * auth_guard: Phoenix :account pipeline [elixir_auth] (./lib/app_web/router.ex:36) (conf 86) - Protected by Phoenix :account pipeline :: 34: pipe_through [:browser, :account] | 36: delete "/keys/:id", PageController, :delete_key | 37: end
    - sources:
      * request_input: path.id [param] (./lib/app_web/router.ex:36) (conf 88) - Route path parameter supplied by the caller. :: ...
    - sinks:
      * redirect: redirect [callee] (./lib/app_web/controllers/page_controller.ex:43) (conf 74) - Potential redirect sink inferred from code or callee name :: ...
    - signals:
      * authz_absence: /settings/keys/:id [heuristic] (./lib/app_web/router.ex:36) (conf 44) - Authenticated endpoint uses a path identifier with no authorization check detected; review for horizontal / vertical privilege escalation. :: ...
```

Each line is `kind: name [source] (path:line) (conf N) - description :: snippet`. The `authz_absence` signal came along because it is linked to `guards`, and it brought its own `sources` evidence. The same guard in JSON:

```json
{
  "kind": "auth_guard",
  "name": "Phoenix :account pipeline",
  "source": "elixir_auth",
  "description": "Protected by Phoenix :account pipeline",
  "path": "./lib/app_web/router.ex",
  "line": 36,
  "confidence": 86,
  "snippet": "34: pipe_through [:browser, :account] | 36: delete \"/keys/:id\", PageController, :delete_key | 37: end"
}
```

| Field | Content |
|---|---|
| `kind` | What the entry is. The tables below list the kinds per bucket |
| `name` | The concrete thing: a callee expression, a parameter as `<type>.<name>` (`query.id`, `json.password`), a guard's label, a route |
| `source` | How Noir found it (see below) |
| `description` | One sentence on why the entry is worth a look |
| `path`, `line` | Where the evidence is. A callee points at its call site, a guard at the middleware or annotation that declares it, most others at the route |
| `confidence` | 0 to 100. It ranks the heuristics against each other. It is not a probability |
| `snippet` | A few numbered source lines around `line`, joined with ` \| ` and capped at about 240 characters |

`source` takes one of these values:

| `source` | Meaning |
|---|---|
| `route`, `detector` | The route itself and the technology that reported it |
| `param` | Read off a parameter the analyzer extracted |
| `param_tagger:<tagger>` | A tag a tagger put on a parameter (`param_tagger:Hunt`) |
| `callee` | Matched on the name of a 1-hop callee, or on the line that calls it |
| `route_source` | Matched on the handler's source text near the route |
| `heuristic` | Derived from other entries in the same context |
| `http_method`, `realtime_method` | Read off the HTTP method, or a WebSocket message handler |
| `mobile_deep_link` | A mobile deep link or exported component |
| `endpoint`, `resolver` | An outbound client declaration, and a GraphQL resolver matched to its operation |
| a tagger or analyzer name | A tag from that tagger (`Admin`, `spring_auth`, `go_security`) or analyzer (`nginx_analyzer`, `odoo_analyzer`) |

`--ai-context` turns on callee collection and runs every tagger, since both feed the context. If you name taggers with `--use-taggers`, only those run.

## Kinds by bucket

These are the kinds Noir emits today.

### guards

| Kind | Meaning |
|---|---|
| `auth_guard` | Authentication: the route checks who the caller is (login required, session check, JWT or API key verification) |
| `authz_guard` | Authorization: the route checks what the caller may do (role, permission, policy, ownership comparison) |
| `csrf_guard` | CSRF protection: token check, `protect_from_forgery`, `SameSite=Strict` |
| `rate_limit_guard` | A throttling or rate-limit layer |

A guard reaches the bucket one of three ways. The [framework auth taggers](@/usage/more_features/tagger/index.md) read the framework's own mechanism (a Spring Security chain, a Phoenix pipeline, an Express middleware, a Go middleware whose body Noir checked) and report `auth_guard` or `authz_guard` with the tagger as `source` and a confidence of 86. The fallback is a name match on the handler's source (`login_required`, `@PreAuthorize`, `before_action :authenticate_user!`), reported as `route_source` with a confidence between 44 and 58. A handler that calls a check of the caller itself (`validateSession(req, res)`, `verifyAuth(...)`, `principal.validate_admin_session()`) is reported with the source `callee` and a confidence of 56 or 60, wherever in the body the call sits. This callee match does not take a `verifyToken` or `validateApiKey` call: the token is as often a reset token or a one-time code the request carries as the caller's own credential. It also stands down on a login-flow route (`/login`, `/verify`, `/reset-password`) that takes a credential in its body or query, where such a call is the login itself. Both name matches only fill a kind the taggers left empty, and the match on the handler's source is the only origin of `csrf_guard` and `rate_limit_guard`.

When a framework says a route admits anonymous callers (tRPC `publicProcedure`, Micronaut `@Secured(IS_ANONYMOUS)`), Noir emits an `anonymous` signal and skips the name match for `auth_guard` and `authz_guard`.

### callees

One kind, `callee`: a call made directly from the handler body. `name` is the call expression (`App.Keys.delete`) and `path:line` is the call site. See [Callee Coverage](@/usage/supported/callee_coverage/index.md) for which frameworks report callees.

### sources

| Kind | Meaning |
|---|---|
| `request_input` | A value the caller controls. One entry per parameter, named `<type>.<name>` with the types `path`, `query`, `header`, `cookie`, `json`, `form`, `file` and `xml`. GraphQL selections are `graphql.field.<name>`. Mobile entry points are `deep_link.mobile_scheme`, `deep_link.universal_link`, `deep_link.android_intent` and `ipc.content_provider`. A cookie the handler reads directly, with no cookie parameter extracted, is `cookie.<name>` from `route_source` |
| `server_secret_source` | A Spring `@Value` secret that the handler returns |
| `cors_policy` | The CORS policy registered for a Spring WebSocket/STOMP endpoint |

### sinks

| Kind | Meaning |
|---|---|
| `sql` | A SQL call: raw SQL, `execute` / `query` on a database-like receiver, a Spring Data repository method |
| `data_store_query` | A document-store or graph-store query (`mongo.query`, a Neo4j client) |
| `command_exec` | An OS command: `exec`, `system`, `spawn`, `popen`, `subprocess`, `ProcessBuilder` |
| `code_eval` | In-process evaluation: `eval`, `new Function`, `instance_eval`, a `ScriptEngine` |
| `deserialization` | Unsafe deserialization: `pickle.loads`, `yaml.load`, `Marshal.load`, `unserialize`, `ObjectInputStream.readObject` |
| `template_injection` | A template built from a string: `render_template_string`, `ERB.new`, `Handlebars.compile` |
| `template_render` | An ordinary template or view render |
| `xss` | HTML output that skips auto-escaping: `innerHTML`, `dangerouslySetInnerHTML`, `html_safe`, `mark_safe`, `v-html`, a `safe` template filter |
| `file_io` | A file-system read or write, a file send, a directory listing |
| `redirect` | A redirect response |
| `outbound_http` | An outbound HTTP request (`fetch`, `axios`, `requests`, `http.Get`, `RestTemplate`, `reqwest`). `name` includes the target URI when it is a literal |
| `mass_assignment` | Request parameters written straight into a model (`update_attributes`, `Model.create(req.body)`) |
| `crypto_weak` | A weak primitive: MD5 or SHA-1, DES, ECB mode, RC4, a non-cryptographic random source |
| `webview_load` | Mobile only. A WebView loads a URL or HTML |
| `intent_redirect` | Mobile only. An intent launched from inbound deep-link data |

A sink has the source `callee` when a callee's name matched and `route_source` when the handler's text did. The handler text contributes at most one sink per kind.

### validators

| Kind | Meaning |
|---|---|
| `validation` | A validate, verify or permit step on the input. A validate or verify of the caller (`validateSession`, `verifyAuth`) is a guard instead |
| `schema_validation` | Schema-based validation that rejects undeclared fields: Pydantic, Zod, Joi, Yup, marshmallow, JSON Schema |
| `type_coercion` | The input is forced to a number or a typed parameter (`parseInt`, `Integer()`, a typed `@PathVariable`) |
| `allowlist_check` | The value is compared against a fixed set |
| `sanitization` | A sanitize, escape, encode or normalize step |
| `query_parameter_binding` | Query parameters are bound through the client API, not concatenated into the query string |
| `existence_validation` | An existence check before the write (`existsBy...`, or a lookup that throws when nothing is found) |
| `uniqueness_validation` | A duplicate or uniqueness check |
| `expiry_validation` | An expiry or validity-window comparison on a token or session |
| `credential_hashing`, `credential_verification` | A Spring Security password encoder's `encode` or `matches` |
| `cookie_httponly`, `cookie_secure` | A cookie set with `HttpOnly` or `Secure` |

### signals

Two signals appear on every endpoint: `route_definition`, named `<METHOD> <url>`, and `technology`, named after the tech that reported the route. The rest fall into five groups.

Route shape:

| Kind | Meaning |
|---|---|
| `state_change` | The method is `POST`, `PUT`, `PATCH` or `DELETE`, or the endpoint is a privileged WebSocket message handler. Left out for pure gRPC and Thrift methods, GraphQL queries, SOAP read operations and a `POST` with no body parameters whose callees are all reads |
| `path_param` | One per path parameter |
| `internal_endpoint` | An outbound client declaration. The application calls this endpoint, it does not serve it |
| `deep_link_input` | A mobile deep link or exported `ContentProvider` receives data from outside the app |
| `graphql_resolver` | The Spring GraphQL resolver that implements this operation |

Parameter names. Each has the source `param` and is named `<type>.<name>`:

| Kind | Typical parameter names |
|---|---|
| `credential_input` | `password`, `token`, `secret`, `api_key`, `authorization`, `jwt`, `bearer`. Also reported from `route_source` when the handler reads `req.body.password` and the analyzer listed no such parameter. A header or cookie is left out when a framework guard is reported for the endpoint, since that guard is what reads it |
| `identifier_input` | `id`, anything ending in `_id` or `Id`, `user`, `account`, `order`, `project` |
| `redirect_input` | `url`, `uri`, `redirect`, `return`, `next`, `continue`, `dest`, `callback` |
| `file_input` | `file`, `upload`, `attachment`, `image`, `filename`, `path` |
| `query_builder_input` | `sort`, `order`, `filter`, `where`, `search`, `select`, `field`, `column` |
| `pii_input` | `email`, `phone`, `ssn`, `dob`, `passport`, `national_id` |
| `html_content_input` | `description`, `html`, `message`, `comment`, `note`, `markdown` |
| `code_input` | `script`, `formula`, `expression`, `command`, `template` |

Tags. Every endpoint tag becomes a signal whose `kind` is the tag name and whose `source` is the tagger: `admin`, `payment`, `webhook`, `file_upload` and the rest of the [taggers](@/usage/more_features/tagger/index.md), framework findings such as `cors`, `csrf-protection`, `rate-limit` and `security-headers`, and analyzer notes such as `graphql-return` or `nginx-host`. Parameter tags (`sqli`, `ssrf`, `idor`) arrive the same way with the source `param_tagger:<tagger>`. Auth tags are the exception: they become guards.

Weakened protections and leaks, matched on the handler's source:

| Kind | Meaning |
|---|---|
| `csrf_exempt` | CSRF protection is switched off for the route (`@csrf_exempt`, `csrf().disable()`, `protect_from_forgery with: :null_session`). Only on state-changing methods |
| `jwt_unsafe` | JWT verification is off or weakened: `verify=False`, algorithm `none`, `ignoreExpiration: true` |
| `cors_open` | A wildcard origin together with `credentials: true` |
| `sensitive_response` | The response includes a credential-like key (`token`, `password`, `secret`) |
| `server_secret_source` | The handler returns a Spring `@Value` secret. Also listed under `sources` |
| `log_injection` | The handler logs request input or a credential |
| `foreign_identifier_write` | An id from the request body is assigned to a different `...Id` field and saved, with no lookup or existence check |

Derived signals, built from the entries above (source `heuristic`):

| Kind | When it appears |
|---|---|
| `guard_absence` | A state-changing endpoint with no guard of any kind and no identifier in its path. Login, logout and password-reset routes are skipped |
| `idor_review` | The same, with an identifier in the path |
| `authz_absence` | A state-changing endpoint has an `auth_guard`, no `authz_guard`, and an identifier in its path |
| `rate_limit_absence` | A state-changing endpoint takes a credential in its body, query or path and has no `rate_limit_guard` |
| `ssrf` | An `outbound_http` sink together with a `redirect_input` |
| `open_redirect` | A `redirect` sink together with a `redirect_input` |
| `path_traversal` | A `file_io` sink together with a `file_input` |
| `object_lookup` | An identifier input together with a lookup callee (`findById`, `getOne`, `repo.get`) |
| `object_write` | A state-changing endpoint with an identifier in its path calls a mutating callee (`create`, `update`, `delete`, `save`) and no lookup callee. Writing an audit-log entry and building a value in memory (`createFormBuilder`, `CreateAPIError`) do not count as mutating |
| `unsafe_method` | A `GET`, `HEAD`, `OPTIONS` or `QUERY` endpoint calls a mutating callee. Skipped when the handler branches on the request method (`request.method ==`, `$request->isMethod()`) or on a form-submission check (`$form->isSubmitted()`, `form.validate_on_submit()`) |
| `priority_review` | The roll-up, described below |

The four absence signals carry low confidence on purpose (28 to 44). Noir can miss a guard that lives in a gateway or in a base class it did not read, so they say "nothing was detected here", not "nothing protects this route".

`priority_review` adds up three things: the review signals on the endpoint (the absence signals, `csrf_exempt`, `jwt_unsafe`, `cors_open`, `open_redirect`, `ssrf`, `path_traversal`, `sensitive_response`, `server_secret_source`, `unsafe_method`, `log_injection`, `deep_link_input`), the distinct heavy sink kinds (`sql`, `data_store_query`, `command_exec`, `code_eval`, `deserialization`, `template_injection`, `xss`, `mass_assignment`, `crypto_weak`, `webview_load`, `intent_redirect`), and one extra point if any of `csrf_exempt`, `jwt_unsafe`, `cors_open` or `open_redirect` is present. A `sql` or `data_store_query` sink does not count next to a `query_parameter_binding` validator, and `xss` does not count next to `sanitization` or `schema_validation`. A total under 2 emits nothing. Otherwise `name` is `high` (confidence 90) when the total is 3 or more, when one of those four signals is present, or when there are two heavy sink kinds, and `medium` (confidence 70) for the rest. Filtering on `kind == "priority_review"` and `confidence >= 80` gives you the high-priority routes.

When a bucket is full, a new entry replaces the lowest-ranked one only if it ranks higher. Derived signals and absence findings outrank parameter-level entries, so a route with many parameters keeps its roll-ups.

## Typical use cases

- **AI SAST**: hand the endpoint inventory plus its AI context to an LLM so it can decide where vulnerabilities are reachable from the attack surface without re-discovering the route structure.
- **Manual triage**: a reviewer skimming a large JSON or SARIF report can sort or filter by sink kind or by `signals` like `guard_absence`.
- **CI gating**: surface `sinks` minus `validators` to flag risky endpoints in pull requests.

## Combine with other flags

```bash
# Plain output with both 1-hop callees and the full AI context block
noir scan . --include callee --ai-context

# JSON output suitable for LLM-driven SAST pipelines
noir scan . --ai-context -f json -o noir-context.json

# OpenAPI export with `x-noir-ai-context` on every operation
noir scan . --ai-context -f oas3 -o spec.json
```

## Completeness notes

- AI context only adds data: endpoints unaffected by any heuristic come out exactly as they would without the flag (no `ai_context` key in serialized models).
- Heuristics are tuned conservatively. Both false positives and false negatives exist, so treat entries as leads to review, not findings.
- Guard / sink / validator patterns improve over time. They are cross-language on purpose, so one context schema works for every framework Noir covers.
- Callee coverage drives much of the AI context. See [Callee Coverage](@/usage/supported/callee_coverage/index.md) for which frameworks expose handler callees today.
