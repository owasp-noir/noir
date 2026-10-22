+++
title = "Mobile Apps"
description = "How Noir extracts Android and iOS deep-link entry points and links them to the code that handles them."
weight = 6
sort_by = "weight"

+++

Noir reports the entry points of an Android or iOS app as endpoints. These are the deep links and exported components the app exposes to the outside world. Noir also links each one to the source code that handles it.

Deep links are a classic mobile attack surface. An externally supplied URL or intent flows into the app and can reach a WebView, an SQL query, or another component.

There is no separate flag. Scan the app's source tree as usual, and Noir picks up the files listed below:

```bash
noir scan path/to/app
```

## What Noir parses

| Platform | Source file | What it yields |
|---|---|---|
| Android | `AndroidManifest.xml` | custom URL-scheme deep links, exported intent components, exported ContentProviders, verified App Links |
| Android | `res/values/strings.xml` | resolves `@string/` references used in schemes / hosts / paths |
| Android | `build.gradle` / `build.gradle.kts` | resolves `${applicationId}` and custom `manifestPlaceholders` used in package / component names / schemes / hosts; supplies the package when the manifest has no `package` attribute |
| Android | `res/navigation/*.xml` | Jetpack Navigation `<deepLink app:uri="...">` deep links; the owning destination becomes the handling component |
| iOS | `Info.plist` (any `*.plist` declaring `CFBundleURLTypes`) | custom URL schemes; also resolves `$(VAR)` / `${VAR}` placeholders from `.xcconfig` / `project.pbxproj` |
| iOS | `*.entitlements` | `associated-domains` `applinks:` universal links and `appclips:` App Clip launch URLs |
| Android | `/.well-known/assetlinks.json` | server-side App Links association (Digital Asset Links) |
| iOS | `apple-app-site-association` | server-side universal-link `paths` / `components` patterns |

The first six rows are the **client** side, declared in the app bundle. The last two are the **server** side: well-known files a host publishes so the OS opens the app for its URLs. Both sides of this association produce `universal-link` endpoints with the same output model.

## Endpoint model

Every mobile entry point is an endpoint with `method = "GET"`. The `protocol` field says what kind of entry point it is:

| protocol | meaning | example URL |
|---|---|---|
| `mobile-scheme` | custom URL-scheme deep link | `myapp://complex/:id` |
| `android-intent` | exported intent component reachable by intent: a data-less action filter, or no intent-filter at all (explicit-intent only) | `intent://com.example.app/.SyncService` |
| `android-provider` | exported ContentProvider reachable by another app through a `content://authority` URI | `content://com.example.app.provider` |
| `universal-link` | verified Android App Link / iOS universal link, or a server-side `assetlinks.json` / `apple-app-site-association` pattern | `https://app.example.com/complex/:id`, `/buy/*` |

In plain output, each kind gets a prefix: `SCHEME`, `INTENT`, `PROVIDER` or `UNIVERSAL`.

The handling component, intent action and category, host, and package go in a per-endpoint metadata map. JSON and YAML output include it. Ordinary HTTP endpoints don't have one.

```
SCHEME myapp://complex/:id
  ○ path: id
  ○ via: .DeepLinkActivity
  ○ action: android.intent.action.VIEW
  ○ category: android.intent.category.DEFAULT
  ○ host: complex
  ○ package: com.example.myapp
```

## Linking to handler code

When the handler source is present in the scan, Noir connects each deep-link endpoint to the code that processes it.

**Android**

* The manifest component (e.g. `.DeepLinkActivity`) is resolved to its `.kt` / `.java` file.
* Its intent-handling methods (`onCreate`, `onNewIntent`, `onReceive`, …) contribute 1-hop callees, that is, the functions they call directly.
* The inputs they read become parameters: `uri.getQueryParameter("q")` → a `query` param (added to the URL), and the `get*Extra` family → an `extra` param.

**iOS**

Deep links are dispatched centrally, so Noir discovers the handlers and attaches them by kind:

* `.onOpenURL` / `application(_:open:)` / `scene(_:openURLContexts:)` → custom schemes.
* The `userActivity` handlers → universal links.
* `URLQueryItem` reads become `query` params.

With `--ai-context`, the handler body feeds Noir's source / sink / guard inference. A deep link that flows into a WebView load or another sink then shows up with the taint path (the route the input takes to that sink) attached.

## Output behavior

| Output | Mobile endpoints |
|---|---|
| Structured inventory (JSON, JSONL, YAML, TOML, SARIF, Markdown table, mermaid, HTML) and the Elasticsearch / webhook exports | Included, because they are part of the app's surface |
| HTTP-shaped output and delivery (cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, Postman, and active probe / proxy delivery) | Left out. An app URL is something you open, not an HTTP request you send |
| `-f adb` (Android) and `-f simctl` (iOS) | Emitted as ready-to-run device commands that launch them |

## Notes and limitations

**General**

* Source code must be present for handler linkage. A manifest- or plist-only scan still yields the endpoints, just without callees, params, or AI context.

**Android**

* **gradle placeholders**: Noir reads the nearest `build.gradle(.kts)` above the manifest. When the same placeholder is declared more than once (e.g. a `buildTypes` override), the first declaration (by convention `defaultConfig`) wins. Variant-specific values are not modeled. A placeholder with no gradle value stays verbatim in the URL, and the endpoint is tagged `unresolved`.
* **Jetpack Navigation**: scheme-less URIs (which match both http and https at runtime) are emitted once under `https`. `{arg}` segments become `:arg` path params, `?key={arg}` query placeholders become `query` params, and a trailing `.*` wildcard keeps the literal prefix.
* **Components without an intent-filter**: an `android:exported="true"` component with no intent-filter is reported as an explicit-intent surface (`android-intent`, with `explicit`/`exported`/`component_type` in metadata). An explicit intent naming the component still reaches it, even with no action, category, or data URI.
  * A filter-less component that is not exported, or is `android:enabled="false"`, is not reported.
  * A guarding `android:permission` is recorded in metadata but does not suppress the surface: `normal`/`dangerous` permissions remain obtainable by another app.
* **ContentProviders**: an exported `<provider>` is reported as an `android-provider` surface, with one `content://authority` endpoint per `android:authorities` entry.
  * The provider class links as the handler (`via`), so its `query` / `insert` / `openFile` methods contribute callees. A raw SQL or file sink shows up in AI context.
  * Permissions are recorded in metadata and never suppress the surface: `android:readPermission` / `android:writePermission` / `android:permission`, `android:grantUriPermissions` (or a `<grant-uri-permission>` child), and the presence of `<path-permission>` overrides.
  * Only an explicitly exported provider is reported (a provider defaults to not-exported on modern SDKs).
  * The effective per-path permission of a `<path-permission>` is flagged but not resolved.

**iOS**

* Binary (compiled) `Info.plist` files are skipped. Source-repo XML plists are parsed.
* Noir also picks up routes written in Swift code for the app's own scheme: router enums compared with `url.host == SomeEnum.case.rawValue` (each case becomes a route), and hardcoded `scheme://host/path` string literals.

**Server-side association files**

* `assetlinks.json` only declares the package association (no paths), so it yields a single `/*` endpoint per app.
* `apple-app-site-association` (AASA) paths (`/buy/*`, `NOT /private/*`) and `components` are emitted individually. AASA exclusions are tagged `excluded`.
* Only the plain-JSON form of AASA is parsed. CMS-signed AASA files (older apps) are skipped.
