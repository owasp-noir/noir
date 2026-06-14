+++
title = "HTTP Client Commands"
description = "Generate executable cURL, HTTPie, and PowerShell commands from Noir scan results."
weight = 1
sort_by = "weight"

+++

Turn discovered endpoints into ready-to-run commands for popular HTTP clients. Use `-u` to set the base URL that gets prepended to each path.

## cURL

[cURL](https://curl.se/) is the most widely used command-line HTTP client. The generated commands include `-i` (show response headers), `-X` (HTTP method), `-d` (request body), `-H` (headers), and `--cookie` as appropriate.

```bash
noir scan . -f curl -u https://www.example.com
```

Example output:
```bash
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
```

## HTTPie

[HTTPie](https://httpie.io/) has a more intuitive syntax than cURL, with colorized output and built-in JSON support.

```bash
noir scan . -f httpie -u https://www.example.com
```

Example output:
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

For Windows environments. Generates [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) commands that work natively without extra tools.

```bash
noir scan . -f powershell -u https://www.example.com
```

Example output:
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```

## ADB (Android)

Mobile entry points are app URLs, not HTTP requests, so the HTTP clients above skip them. `-f adb` does the inverse: it turns the Android deep links, intent components, and content providers Noir discovers into [Android Debug Bridge](https://developer.android.com/tools/adb) commands you can run against a connected device or emulator.

`adb` is Android-only, so the format emits commands for Android-originated entry points and skips everything it can't launch — HTTP endpoints, iOS schemes (use [`-f simctl`](#simctl-ios)), and bare App Links domain associations — each reported as a one-line warning to stderr (the command list on stdout stays pipe-clean).

```bash
noir scan ./my-android-app -f adb
```

Example output:
```bash
# custom-scheme deep link / verified app link → am start with a VIEW intent
adb shell am start -a 'android.intent.action.VIEW' -c 'android.intent.category.BROWSABLE' -d 'myapp://host/path' -p 'com.example.app'
# explicit activity / service / receiver → am start / startservice / broadcast
adb shell am start -n 'com.example.app/.ExportedActivity'
adb shell am startservice -n 'com.example.app/.SyncService'
adb shell am broadcast -n 'com.example.app/.BootReceiver'
# exported ContentProvider → content query
adb shell content query --uri 'content://com.example.app.provider'
```

The action, category, and package come from the manifest's intent-filter, so each launch matches the declared filter. Intent extras discovered in the handler are emitted as `--es` string extras (empty templates you can fill, or seed with `--pvalue`). See [Mobile Apps](../../supported/mobile/) for how these entry points are extracted.

## simctl (iOS)

`-f simctl` is the iOS counterpart to `-f adb`: it turns the iOS custom-scheme deep links and universal links Noir discovers into [`xcrun simctl openurl`](https://developer.apple.com/documentation/xcode/simulator) commands that open them on a booted iOS Simulator. iOS has no intent or content-provider analog, so every command is a single `openurl`.

```bash
noir scan ./my-ios-app -f simctl
```

Example output:
```bash
xcrun simctl openurl booted 'myapp://host/path?token='
xcrun simctl openurl booted 'https://app.example.com/buy'
```

Like `-f adb`, `simctl` is platform-specific: it emits commands for iOS-originated entry points and skips what it can't open — HTTP endpoints, Android entry points (use `-f adb`), and bare App Links domain associations — each reported as a one-line warning to stderr.

## Filling Parameter Values

By default Noir leaves parameter values empty (`x-api-key=`, `query=`, …) so the commands work as templates. Pre-populate values with `--pvalue`, handy when you want a script you can run as-is, or when you want to seed fuzzing input.

```
--pvalue TYPE=VALUE     # repeatable
```

| `TYPE`            | Scope                                                |
|-------------------|------------------------------------------------------|
| `any` (or omit)   | Every parameter type                                 |
| `query`           | Query string                                         |
| `form`            | Form body (`application/x-www-form-urlencoded`)      |
| `json`            | JSON body                                            |
| `header`          | Request headers                                      |
| `cookie`          | Cookies                                              |
| `path`            | Path parameters                                      |

`VALUE` accepts two forms:

| Form | Behavior |
|---|---|
| `<value>` | Used for every parameter of the targeted type |
| `<name>=<value>` or `<name>:<value>` | Used only for parameters named `<name>` |

`--pvalue` is repeatable, and per-type rules win over the generic `any` scope when both match.

```bash
# Fill every parameter with `test`
noir scan . -f curl -u https://example.com --pvalue "test"

# Fill only the `Authorization` header and `id` path param
noir scan . -f curl -u https://example.com \
  --pvalue "header=Authorization=Bearer xyz" \
  --pvalue "path=id=42"

# Mix: default `1` for query, but `limit` always 10
noir scan . -f curl -u https://example.com \
  --pvalue "query=1" \
  --pvalue "query=limit=10"
```

The same flag applies to HTTPie and PowerShell output, and feeds downstream into the OpenAPI, Postman, and JSON formats wherever values are rendered.

> **Legacy:** v0's `--set-pvalue`, `--set-pvalue-query`, `--set-pvalue-header`,
> etc. still work as silent aliases in v1.x. New scripts should prefer
> the unified `--pvalue TYPE=VALUE` form above.
