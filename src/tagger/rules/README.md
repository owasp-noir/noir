# Tag rules

Each `*.yml` file here is one tagger. Files are embedded into the binary at compile time (`embed.cr`), so adding a file is the whole registration: the rule's `key` becomes a `--use-taggers` value, and the tagger is listed by `noir list taggers` and runs under `-T`.

```yaml
key: payment                 # file must be named payment.yml; [a-z0-9_]+
name: Payment Tagger         # shown by `noir list taggers`
summary: Identifies payment and financial transaction endpoints
order: 120                   # run order among all taggers; spaced by 10
tag:
  name: payment              # optional, defaults to key
  tagger: Payment
  description: Payment or financial transaction endpoint; ...
match:
  any:
    - path_segment: [payment, checkout, billing]
    - all:
        - param: { name: amount }
        - param: { name: [currency, currency_code] }
examples:
  match:
    - { method: POST, url: /api/checkout }
  no_match:
    - { url: /api/users }
```

## Conditions

| Key | True when |
|---|---|
| `any: [...]` | any child condition is true |
| `all: [...]` | every child condition is true. A mapping with several keys means the same thing |
| `not: {...}` | the child condition is false |
| `at_least: { count: N, of: [...] }` | at least N of the listed conditions are true |
| `path_segment: [...]` | a URL segment is in the list. The URL is lowercased and split on `/ - _ .`, so `/wp-admin` has an `admin` segment and `/badminton` does not |
| `url_contains: [...]` | the lowercased URL contains one of the strings |
| `method: [...]` / `method_not: [...]` | the method is (not) in the list. `safe` stands for GET, HEAD, OPTIONS and QUERY |
| `protocol: [...]` | the endpoint protocol (`http`, `ws`, …) is in the list |
| `param: {...}` | at least `min` (default 1) params pass every filter given |

`param` filters:

- `name`: parameter names. Compared after lowercasing and removing `-` and `_`, so `is_admin`, `isAdmin` and `is-admin` are the same name.
- `name_prefix`: names starting with any of these (same normalization). Given together with `name`, a param passes if it matches either.
- `type`: `query`, `json`, `form`, `header`, `cookie`, `path`, …
- `value_contains`: the lowercased value contains one of the strings.
- `min`: how many params must pass.

A single string works wherever a list does. Unknown keys, empty lists and a `path_segment` containing a separator are load errors.

## Testing

`examples` is the test. `spec/unit_test/tagger/rule_tagger_spec.cr` checks that every rule has both lists, tags every `match` example and tags no `no_match` example. An example is `{ method, url, protocol, params: [{ name, value, type }] }`; method defaults to GET, protocol to http and param type to query.

Put the false positive you are guarding against in `no_match`. Run `just spec-build && ./bin/noir_spec -e "tag rules"`.

If a tagger needs logic these conditions can't express, write it in Crystal under `src/tagger/taggers/` instead.

## Your own rules

The same format works outside this directory: `noir scan --tagger-rules PATH` (or `tagger_rules_path` in the config file) loads rule files or directories at scan time. Those rules always run, their keys must not collide with an existing tagger, and wrong `examples` are reported as warnings instead of failing a spec. The file-name-matches-key requirement applies only to the built-in rules. `noir list taggers --tagger-rules PATH` lists them and checks their examples without scanning.
