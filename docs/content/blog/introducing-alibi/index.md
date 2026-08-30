+++
title = "alibi: the endpoints that can't account for themselves"
description = "A companion tool that runs Noir once per view and cross-examines code, docs, traffic, gateway, and infra against each other."
date = "2026-08-30"
tags = ["alibi", "release", "tooling"]
authors = ["hahwul"]
template = "blog_post"
+++

alibi is out: a companion tool that runs Noir once per view of your attack surface and cross-examines the results. It lives at [owasp-noir/alibi](https://github.com/owasp-noir/alibi).

The premise fits in a paragraph. Noir reads the same surface from five directions:

| View | Read from |
| --- | --- |
| **code** | 200+ analyzers across 33 languages |
| **doc** | OpenAPI, RAML, WSDL, GraphQL SDL, AsyncAPI, gRPC, Smithy, TypeSpec, OData, OpenRPC |
| **traffic** | HAR, mitmproxy, Burp, Caido, ZAP, Postman, Insomnia, Bruno, `.http` |
| **gateway** | nginx, Apache, Envoy, Kong, Traefik, APISIX, Caddy, Istio, Kubernetes Ingress and Gateway API |
| **infra** | Terraform, CloudFormation, CDK, Serverless, Vercel, Netlify, Wrangler, Azure Functions, Kamal |

Each view is a claim about what exists. The code says "this route is implemented." A contract says "this endpoint is promised." A capture file says "this URL took a real request." An endpoint that shows up in one view should be able to account for itself in the others, and when it can't, someone should go look: that gap is a shadow API, a phantom contract, a gateway rule that routes to nothing. Noir collects all five claims and stops there, by design. alibi asks whether they agree.

## The one-scan plan, and why it failed

My first plan was a single scan. Noir labels every endpoint with the technology that found it, so I figured the five views would fall out of one JSON for free.

They don't. Noir deduplicates by `(method, url)` across every analyzer, and for a discovery tool that's correct: a Flask route and an OpenAPI path spelled identically *are* one endpoint. For a comparison it's fatal, and fatal in the worst direction, because the better two views agree, the more of their endpoints merge into single records and the more corroboration vanishes. Scan casdoor whole and you get 372 code endpoints against 9 documented ones. Scan its `swagger/` directory alone and the spec holds 235.

So alibi runs Noir once per view, restricting each pass with `--only-techs`, and joins the results itself. Noir needed no changes for any of this, and alibi parses no API formats of its own. Its only input is Noir's JSON.

That's also the reason it's a separate repository, and a Python one. Noir grew from 19k to 198k lines in about a year. I'd rather grow the ecosystem sideways than keep growing the binary, and the contribution bar for a comparison tool should be low.

## What a run looks like

```console
$ alibi scan ./casdoor
alibi  ·  1 source  ·  377 endpoints

  code 372   doc 235

  230 corroborated -- vouched for by more than one view

  19 endpoints nearly matched another view -- these may be matching failures, not real gaps

SHADOW  Shadow API -- Implemented, but no contract describes it
  134 findings  ·  4 critical, 57 high, 62 medium, 11 low

  critical POST    /api/upload-groups        router.go:87
           upload paths carry more consequence than reads
  critical POST    /api/upload-permissions   router.go:208
```

Eight rules ship: `SHADOW`, `PHANTOM`, `ORPHAN`, `LIVE_UNDOC`, `DANGLING`, `DRIFT`, `UNEXPOSED`, `COLD`. Severity then shifts on what Noir's taggers saw on the endpoint: file uploads, personal data, state-changing methods, signs of authentication.

## Most of the work wasn't the comparison

Joining five endpoint lists is a weekend project. The real work was keeping the report honest, and every guard in alibi exists because a real repository produced a confident wrong answer first.

The first full run on casdoor marked nearly half the findings critical. The promotion rule was "no sign of authentication", and Noir's auth taggers had tagged nine endpoints out of almost four hundred, so "no sign" was true nearly everywhere and meant nothing. The rule now runs the other way: the presence of a signal moves severity, and an adjustment keyed to a missing tag applies only when that tag exists somewhere in the scan.

Argo CD reported 58 shadow APIs and 198 phantom contracts, none of them real. Its Go code registers `/api`; its OpenAPI documents 198 paths beneath it. Same surface, two granularities, not a single shared endpoint. Zero overlap between two populated views now reads as "this comparison failed", so the rules hold back and the report explains why instead of flooding.

NetBox nearly shipped the worst answer of all. Its API documentation is one 12.35MB OpenAPI file, Noir skipped it for exceeding the file-size cap, and the draft report concluded that the project documents nothing. Not incomplete. Wrong, and confident about it. Noir now gives specification documents their own size budget ([#2671](https://github.com/owasp-noir/noir/pull/2671)), and alibi prints whatever Noir reported it couldn't read above the findings, because a missing view and an empty view mean opposite things.

The same caution runs through the rest. A finding whose endpoint nearly matches another view (same path under a different verb, a parameter where the other side has a literal) is demoted and flagged, because "in code but not in the docs" is indistinguishable from "in both, but alibi failed to line them up". Snapshots record which rules actually evaluated, because dropping the contracts directory from one run makes `SHADOW` evaluate nothing, and to a naive diff that looks exactly like every shadow API having been closed.

Under all of it sits one normalization rule: a path parameter's name is not part of its identity. `/users/<int:user_id>`, `/users/{id}` and `/users/:id` describe the same slot; what matters is its position and whether it spans a `/`. Before trusting that rule I ran it over every route fixture in Noir's own test tree, 3,195 URLs across 33 languages.

## Where it stops

alibi compares what Noir can read, and a view read at the wrong granularity is worse than one not read at all. Argo CD sits at that ceiling above. authentik assembles its URLconf at runtime by importing every installed app's `urls` module, which no static reader can follow. flipt mounts a gRPC gateway, so its Go source holds exactly one route. All three are held back by the overlap guard, and the report names the reason rather than inventing findings.

NetBox is the case that shows the intended workflow, though. One repository, two surfaces: a server-rendered web UI and a DRF REST API, and only the second has a contract. Scanned whole it reports 746 findings, most of them the true but useless observation that a web UI is not in an API specification. Scoped to what the contract covers:

```console
$ alibi scan ./netbox --ignore '^/(?!api/)'
```

Three shadow APIs remain (`/api/plugins`, `/api/schema/redoc`, `/api/schema/swagger-ui`), all genuinely served and all genuinely absent from the schema.

Building this fed fixes back into Noir along the way: split OpenAPI documents that `$ref` their operations out to other files ([#2673](https://github.com/owasp-noir/noir/pull/2673)), the DRF surface a Django project actually exposes ([#2672](https://github.com/owasp-noir/noir/pull/2672)), and the spec size budget above. That loop, a companion tool stress-testing the scanner, may turn out to be alibi's second job.

## Try it

```bash
uv tool install noir-alibi   # or: pipx install noir-alibi
alibi scan ./service ./contracts ./prod.har
```

It needs noir 1.0.0 or newer on `PATH`. `-f sarif` uploads to code scanning, `--fail-on high` gates a build, and an `.alibi.yml` next to the source suppresses the gaps that are intentional.

It's early. If alibi tells you something that isn't true, that's exactly the kind of bug the whole tool is organized around catching, so please [open an issue](https://github.com/owasp-noir/alibi/issues). Happy hunting :D
