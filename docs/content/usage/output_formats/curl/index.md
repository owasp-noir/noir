+++
title = "HTTP Client Commands"
description = "Generate executable cURL, HTTPie, and PowerShell commands from Noir scan results."
weight = 1
sort_by = "weight"

+++

Turn discovered endpoints into ready-to-run commands for common HTTP clients. Use `-u` to set the base URL that gets prepended to each path. Without `-u`, each command targets the bare path (`'/query'`).

## cURL

[cURL](https://curl.se/) is the most widely used command-line HTTP client. The generated commands use these options as needed:

- `-i` shows response headers.
- `-g` turns off URL globbing, so `{id}` and `[..]` are sent literally.
- `-X` sets the HTTP method. HEAD gets `-I` instead.
- `--data-raw` sends urlencoded or JSON bodies, with the matching `Content-Type` header.
- `--form-string` and `-F` send multipart uploads.
- `-H` adds headers. An empty header prints as `'Name;'`.
- `--cookie` sends cookies.

```bash
noir scan . -f curl -u https://www.example.com
```

Example output:
```bash
curl -i -g -X 'GET' 'https://www.example.com/' -H 'x-api-key;'
curl -i -g -X 'POST' 'https://www.example.com/query' --data-raw 'query=' -H 'Content-Type: application/x-www-form-urlencoded' --cookie 'my_auth='
curl -i -g -X 'GET' 'https://www.example.com/token' --data-raw 'client_id=&redirect_url=&grant_type=' -H 'Content-Type: application/x-www-form-urlencoded'
```

## HTTPie

[HTTPie](https://httpie.io/) is a command-line HTTP client with a shorter syntax than cURL.

```bash
noir scan . -f httpie -u https://www.example.com
```

Example output:
```bash
http 'GET' 'https://www.example.com/' 'x-api-key: '
http --form 'POST' 'https://www.example.com/query' 'query=' 'Cookie:my_auth='
http --form 'GET' 'https://www.example.com/token' 'client_id=' 'redirect_url=' 'grant_type='
```

## PowerShell

For Windows. Generates [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) commands that need no extra tools.

```bash
noir scan . -f powershell -u https://www.example.com
```

Example output:
```powershell
Invoke-WebRequest -Method "GET" -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method "POST" -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method "GET" -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```


## File uploads (multipart)

When an endpoint has a `param_type: file` field (a multipart upload found in the code), the HTTP client formats switch from urlencoded (`--data-raw` / `-Body`) to multipart so the file part is kept:

| Format | Shape |
|--------|-------|
| cURL (`-f curl`) | `--form-string 'field=value'` for other form fields (sent verbatim, so a value starting with `@` or `<` is not read as a file), `-F 'avatar=@avatar'` for each file |
| HTTPie (`-f httpie`) | `--form` with `field=value` and `avatar@avatar` |
| PowerShell (`-f powershell`) | `-Form @{ "field"="…"; "avatar"=Get-Item -Path "avatar" }` (PowerShell sets the multipart `Content-Type` itself) |

Example (`POST /upload` with form field `title` and file field `avatar`):

```bash
# cURL
curl -i -g -X 'POST' 'https://www.example.com/upload' --form-string 'title=' -F 'avatar=@avatar'

# HTTPie
http --form 'POST' 'https://www.example.com/upload' 'title=' 'avatar@avatar'

# PowerShell
Invoke-WebRequest -Method "POST" -Uri "https://www.example.com/upload" -Form @{"title"=""; "avatar"=Get-Item -Path "avatar"}
```

The file path is a placeholder named after the field. `--pvalue` does not fill file fields, so replace the path by hand. Without a file field, output stays on the urlencoded examples above.

## XML request bodies

`param_type: xml` (Play `asXml`, Tapir `xmlBody`, and similar whole-body XML params) is not turned into a request body in the HTTP client formats (`curl`, `httpie`, `powershell`). Those formats only build `form` / `json` bodies (plus the multipart `file` uploads above), so an endpoint whose only body params are XML prints as a command with just the URL and headers.

For XML bodies, use one of:

- `-f oas2` / `-f oas3`: `application/xml` requestBody (see [OpenAPI](@/usage/output_formats/openapi/index.md))
- `-f postman`: raw body with `Content-Type: application/xml` (see [Additional Formats](@/usage/output_formats/more/index.md#postman-collection))
- `-f json` / `-f yaml` / plain: the `xml` param type is preserved on the endpoint record

The HTML report's "copy as curl" button uses the same curl builder, so it has the same limitation.

## ADB (Android)

Mobile entry points are app URLs, not HTTP requests, so the HTTP clients above skip them. `-f adb` covers only those: it turns the Android deep links, intent components, and content providers Noir discovers into [Android Debug Bridge](https://developer.android.com/tools/adb) commands you can run against a connected device or emulator.

`adb` is Android-only. It emits commands for Android entry points and skips everything it can't launch: HTTP endpoints, iOS schemes (use [`-f simctl`](#simctl-ios)), and bare App Links domain associations. Each skipped kind gets a one-line warning on stderr, so stdout stays clean for piping.

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

The action, category, and package come from the manifest's intent-filter, so each launch matches the declared filter. Intent extras found in the handler are emitted as `--es` string extras with empty values for you to fill in (`--pvalue` does not reach them). See [Mobile Apps](../../supported/mobile/) for how these entry points are extracted.

## simctl (iOS)

`-f simctl` is the iOS counterpart to `-f adb`: it turns the iOS custom-scheme deep links and universal links Noir discovers into [`xcrun simctl openurl`](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) commands that open them on a booted iOS Simulator. iOS has no intent or content-provider analog, so every command is a single `openurl`.

```bash
noir scan ./my-ios-app -f simctl
```

Example output:
```bash
xcrun simctl openurl booted 'myapp://host/path?token='
xcrun simctl openurl booted 'https://app.example.com/buy'
```

Like `-f adb`, `simctl` is platform-specific: it emits commands for iOS entry points and skips what it can't open: HTTP endpoints, Android entry points (use `-f adb`), and bare App Links domain associations. Each skipped kind gets a one-line warning on stderr.

## Filling Parameter Values

By default Noir leaves parameter values empty (`x-api-key=`, `query=`, ...) so the commands work as templates. Use `--pvalue` to fill them in, for a script you can run as-is or for fuzzing seeds.

```
--pvalue TYPE=VALUE     # repeatable
```

| `TYPE`            | Scope                                                |
|-------------------|------------------------------------------------------|
| `any` (or no `TYPE=` prefix, when the value has no `=`) | Every parameter type except `file` and `xml` |
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
| `<name>=<value>` or `<name>:<value>` | Used only for parameters named `<name>`. The `=` form needs an explicit `TYPE=` (`any=` works); the `:` form works without one |

`--pvalue` is repeatable. A rule that names the parameter wins over a type-wide value, and a per-type rule wins over an `any` rule of the same kind.

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

The same values show up in HTTPie and PowerShell output, and in every other format that prints parameter values (OpenAPI, Postman, JSON, ...).

> Legacy: v0's `--set-pvalue`, `--set-pvalue-query`, `--set-pvalue-header`,
> etc. still work as silent aliases in v1.x. New scripts should use
> `--pvalue TYPE=VALUE`.
