+++
title = "Callee Coverage"
description = "Framework coverage for Noir's best-effort per-endpoint 1-hop callee extraction."
weight = 4
sort_by = "weight"

+++

Noir can attach best-effort 1-hop handler callees to endpoints. A callee is a function, method, or framework call observed directly inside the route handler body. It helps AI SAST tools and code reviewers decide where to inspect next.

Use `--include callee` to show callees in plain output:

```bash
noir scan . --include callee
```

Model-based formats such as JSON, JSONL, YAML, TOML, and plain model serialization include the `callees` field through the endpoint model. OpenAPI 2.0 and 3.0 expose callees as the operation-level `x-noir-callees` extension, SARIF stores them in `result.properties.noir.callees`, and Postman collections add a human-readable list to the item description. Purpose-specific command and filter outputs such as cURL, HTTPie, PowerShell, only-url, and only-param omit callees to keep their primary output stable.

The `path` and `line` values are best-effort locations. Most analyzers report the call site; analyzers with definition resolution report the callee definition when reachable, and keep the call-site location otherwise.

## Coverage Matrix

This matrix lists frameworks with functional test coverage for callee extraction. Endpoint detection can still be supported for frameworks not listed here, but AI consumers should treat their callee coverage as unavailable or unverified.

| Language | Frameworks with callee coverage |
|----------|---------------------------------|
| C# | ASP.NET Core MVC, ASP.NET MVC, FastEndpoints |
| Clojure | Compojure |
| C++ | Crow, Drogon |
| Crystal | Amber, Grip, Kemal, Lucky, Marten |
| Dart | Dart Frog, Serverpod, Shelf |
| Elixir | Phoenix, Plug |
| F# | Giraffe |
| Go | Beego, Chi, Echo, fasthttp, Fiber, Gin, GoFrame, Goyave, go-zero, Hertz, httprouter, Iris, Gorilla Mux |
| Groovy | Grails |
| Haskell | Scotty, Servant, Yesod |
| Java | Armeria, Dropwizard, Javalin, JAX-RS, Micronaut, Play, Quarkus, Spark, Spring, Vert.x |
| JavaScript | Express, Fastify, Hono, Koa, NestJS, Next.js, Nitro, Nuxt, Remix, Restify, SvelteKit |
| Kotlin | http4k, Ktor, Spring |
| Lua | Lapis |
| Perl | Mojolicious |
| PHP | CakePHP, CodeIgniter, Hyperf, Laravel, Pure PHP, Slim, Symfony, Yii |
| Python | Aiohttp, Bottle, Django, Falcon, FastAPI, Flask, Litestar, Pyramid, Quart, Sanic, Starlette, Tornado |
| Ruby | Grape, Hanami, Rails, Roda, Sinatra |
| Rust | Actix Web, Axum, Gotham, Loco, Poem, Rocket, RWF, Salvo, Tide, Warp |
| Scala | Akka HTTP, http4s, Scalatra, ZIO HTTP |
| Swift | Hummingbird, Kitura, Vapor |
| TypeScript | NestJS |

## Completeness Notes

- Callees are 1-hop only. Noir does not build a transitive call graph.
- Dynamic dispatch, middleware chains, decorators, macro expansion, generated code, and reflection can hide calls from static extraction.
- Named handler frameworks usually have better callee coverage than heavily dynamic or inline callback-heavy frameworks.
- Definition resolution is incremental and currently analyzer-specific.
- Calls are deduplicated and capped per endpoint to keep output compact for downstream tools.
- Framework helpers such as renderers and request accessors are intentionally kept because they describe how the endpoint handles input and output.
