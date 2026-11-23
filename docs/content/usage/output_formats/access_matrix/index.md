+++
title = "Access Matrix"
description = "A Markdown table of which callers can reach each endpoint, read from the guards Noir finds in source."
weight = 5
sort_by = "weight"

+++

`-f access-matrix` prints a Markdown table with one row per endpoint and one column per kind of caller. Each cell says whether that caller passes the guards Noir found on the route.

## Usage

```bash
noir scan . -f access-matrix --no-log
```

The matrix is built from tags, so this format runs every tagger unless you pick taggers yourself with `-T` or `--use-taggers`. The log shows `Running all taggers (implied by -f access-matrix).`

## Example output

```
| Endpoint | `anonymous` | `authenticated` | `role:ADMIN` | `role:MANAGER` | `role:USER` | Requires |
| --- | --- | --- | --- | --- | --- | --- |
| `DELETE /api/admin/users/{id}` | - | - | Y | - | - | `role:ADMIN` |
| `POST /api/posts` | - | - | - | - | Y | `role:USER & authenticated` |
| `DELETE /api/posts/{id}` | - | - | Y | Y | - | `(role:ADMIN \| role:MANAGER) & authenticated` |
| `GET /posts/:id` | - | ? | ? | ? | ? | `authenticated & unresolved` |
| `GET /api/public/health` | Y | Y | Y | Y | Y | no guard found |

Y allowed, - denied, ? unknown (a guard noir could not read)
```

## Columns

| Column | Meaning |
|---|---|
| `anonymous` | A caller who is not signed in. |
| `authenticated` | A signed-in caller with no role, permission, or scope. |
| `role:X`, `permission:X`, `scope:X` | A signed-in caller who holds exactly that one value. Noir adds a column for every value that some endpoint in the scan requires. |
| Requires | The requirement Noir read, described below. |

## Cells

| Mark | Meaning |
|---|---|
| `Y` | The caller passes every guard Noir found. |
| `-` | At least one guard rejects the caller. |
| `?` | No guard rejects the caller, but one guard is `unresolved`, so Noir cannot say. |

A `-` wins over a `?`. If one guard rejects the caller, the cell is `-` even when another guard is unknown.

## The Requires column

The requirement is a list of conditions that must all hold, joined with `&`. A condition in parentheses holds when any of its values does, joined with `|`.

- `unresolved` is a guard that Noir saw but could not read, such as a bean call, a constant from another file, or a custom guard class. The JSON output keeps the source text of each one in the tag's `requires` field.
- `deny` is a guard that rejects every caller, such as Spring `denyAll()`. Every cell in its row is `-`.
- `no guard found` means Noir found no guard on the route. It does not mean the route is public by declaration. A route that the source marks as open to anonymous callers, such as a Quarkus `@PermitAll` method that Noir tags `anonymous`, shows `anonymous` here instead.

## Where the requirement comes from

Noir reads the requirement from the endpoint's tags:

- A tag with a `requires` field (see [JSON output](../json/)) gives its conditions as written. Today the `spring_auth` tagger fills it.
- An `auth` tag from any other tagger reads as `authenticated & unresolved`. The tag says a guard exists, but not what it checks.
- An `authz` tag from any other tagger reads as `unresolved`.
- An `anonymous` tag reads as `anonymous`. It does not lift a guard from another tag: a route whose handler admits anonymous callers but whose filter chain requires a sign-in still shows `-` in the `anonymous` column.

The conditions from all tags on an endpoint must all hold. The table leaves out outbound client calls (a Feign or `@HttpExchange` declaration), which the application calls and does not serve. Non-HTTP routes are included.
