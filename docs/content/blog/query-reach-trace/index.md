+++
title = "After the endpoint list: query, reach, and trace"
description = "Use Noir's endpoint report to narrow a review, find routes connected to a source file, and match a request to its route."
date = "2026-11-06"
tags = ["tips", "query", "reach", "trace", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

An endpoint list is a good place to start a review. Then you find a shared helper, a suspicious request, or a group of routes that needs a closer look. Reading the whole list again does not answer those questions.

Noir's `query`, `reach`, and `trace` let you start with what you already know. A filter, a source file, or a concrete request can lead you to the next piece of code to read.

## Keep the report, change the question

Each command can scan a codebase directly. During a review, though, the questions keep changing. Saving a report lets you ask them without scanning again.

The examples below use the Flask callee fixture in the [Noir repository](https://github.com/owasp-noir/noir/tree/main/spec/functional_test/fixtures/python/flask_callees). They were run with Noir 1.5.0, from the repository root, with `noir` on `PATH`. This fixture has a form handler, an order lookup, and helpers that both handlers call. No running Flask application is needed.

```bash
cd spec/functional_test/fixtures/python/flask_callees
noir scan . --ai-context --include callee -f json \
	-o /tmp/noir-review.json --no-log > /dev/null
```

`--ai-context` collects static review context. It does not need an AI provider. `--include callee` keeps the recorded calls in the report too. The stdout redirect hides the duplicate report that `scan` prints while `-o` saves it.

There is a difference between a live scan and `--from`. A live query command enables all AI context and callee collection implicitly. A saved report contains only what the original scan collected. Reading it does not add missing guards or sinks, and changing the application does not update the report. Regenerate it when the source changes.

## Query gives the review a starting point

Suppose you want to inspect POST handlers that accept a form field named `name`, without a recorded authentication or authorization guard.

```bash
noir query --method POST --no-guard --param name --param-type form \
	--from /tmp/noir-review.json -f text
```

```text
POST /users  ./app.py:7  python_flask  handler=create_user@./app.py:8  signals=guard_absence
```

That leaves `create_user` at `app.py:8` to read. Different filters combine with AND. Values within a comma-separated filter combine with OR, so `--method GET,POST` accepts either method. When you specify both a parameter name and type, the same parameter must satisfy both.

`--no-guard` means Noir recorded no authentication or authorization guard. It does not prove that the route is public. Unresolved middleware or an upstream gateway can change the answer. Rate limiting and CSRF checks do not count as authentication guards either.

If your report has database sinks, `--sink sql` can narrow the review further. A recorded sink is a reason to read the code, not a finding of SQL injection.

## Reach starts where the code changed

Now suppose the change is in `run_sql_query`, defined at `helpers.py:5`. Which endpoints need another look?

```bash
noir reach helpers.py:5 --from /tmp/noir-review.json -f text
```

```text
POST /users  ./app.py:7  python_flask  handler=create_user@./app.py:8  signals=guard_absence  via=callee:run_sql_query@./helpers.py:5,callee:build_user_query@./helpers.py:1,callee:notify_admin@./helpers.py:10,callee:log_audit@./helpers.py:14
GET /orders/<order_id>  ./app.py:17  python_flask  handler=get_order@./app.py:18  signals=path_param,idor  via=callee:run_sql_query@./helpers.py:5,callee:build_user_query@./helpers.py:1
```

Both `/users` and `/orders/<order_id>` appear. Their `via` fields point to recorded callees in `helpers.py`, with `run_sql_query` first because its definition is closest to the requested line.

The line number ranks matches. It does not restrict the result to a function containing that line. Noir records declaration locations rather than complete function spans. JSON and JSONL output also include `nearest_line` when you supply a line number.

`reach` uses path suffixes, so `helpers.py` is enough here. In a larger repository, use a longer suffix to distinguish files with the same name. It checks recorded route, handler, callee, guard, source, sink, and validator locations. It is not a complete call graph, and it does not follow inheritance or dynamic loading. An empty result means no recorded connection matched, not that a change cannot affect a route.

## Trace starts with the request you have

A proxy log usually has a concrete path, while the application declares a route template. Here is the order lookup from the same report:

```bash
noir trace "GET /orders/42" --from /tmp/noir-review.json -f text
```

```text
GET /orders/<order_id>  ./app.py:17  python_flask  matched_by=pattern  handler=get_order@./app.py:18  signals=path_param,idor
```

`matched_by=pattern` explains why `/orders/42` matches `/orders/<order_id>`. This is a lookup in the saved report. It sends no HTTP request.

Include the method when you know it. Without a method, Noir returns matching routes across methods. HEAD can match a GET route. If several routes match, the most specific matches come first.

A catch-all can accept a misspelled path too. When only wildcard or prefix routes match, `trace` also looks for nearby candidates. A complete miss exits with code 1 and includes any candidates it found. JSON and JSONL output carry the full matched endpoint under `endpoint`, so you can inspect its recorded parameters and context without another scan.

## Use the result to choose what to read next

There is no required order. Start with `query` when you know a property, `reach` when you have a changed file, or `trace` when you have a request. Then check the evidence against the code.

Text output keeps the terminal readable. JSONL is the default for scripts, and `--full` adds the full endpoint record to `query` and `reach` results. `--limit` caps the printed rows. `--count` prints a count, but if you combine the two, it counts only the limited rows. All three commands exit with code 1 when nothing matches.

Keep scan paths and scan-only flags on the original scan. Noir rejects them alongside `--from`, because that command reads a report rather than scanning a directory. The [CLI reference](@/usage/cli_commands/_index.md#trace-reach-query) has the full filter list and output options.
