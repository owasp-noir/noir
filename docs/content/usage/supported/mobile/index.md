+++
title = "Mobile Apps"
description = "How Noir extracts Android and iOS deep-link entry points and links them to the code that handles them."
weight = 6
sort_by = "weight"

+++

Noir extracts mobile app entry points — the deep links and exported components an Android or iOS app exposes to the outside world — as endpoints, and links them to the source code that handles them. Deep links are a classic mobile attack surface: an externally supplied URL or intent flows into the app and can reach a WebView, an SQL query, or another component.

## What Noir parses

| Platform | Source file | What it yields |
|---|---|---|
| Android | `AndroidManifest.xml` | custom URL-scheme deep links, exported intent components, exported ContentProviders, verified App Links |
| Android | `res/values/strings.xml` | resolves `@string/` references used in schemes / hosts / paths |
| Android | `build.gradle` / `build.gradle.kts` | resolves `${applicationId}` and custom `manifestPlaceholders` used in package / component names / schemes / hosts; supplies the package when the manifest has no `package` attribute |
| Android | `res/navigation/*.xml` | Jetpack Navigation `<deepLink app:uri="...">` deep links — the owning destination becomes the handling component |
| iOS | `Info.plist` (any `*.plist` declaring `CFBundleURLTypes`) | custom URL schemes — also resolves `$(VAR)` / `${VAR}` placeholders from `.xcconfig` / `project.pbxproj` |
| iOS | `*.entitlements` | `associated-domains` `applinks:` universal links and `appclips:` App Clip launch URLs |
| Android | `/.well-known/assetlinks.json` | server-side App Links association (Digital Asset Links) |
| iOS | `apple-app-site-association` | server-side universal-link `paths` / `components` patterns |

The first six rows are the **client** side of the association, declared in the app bundle. The last two are the **server** side — the well-known files a host publishes so the OS opens the app for its URLs. Both flow through the same `universal-link` protocol and output model.

## Endpoint model

Mobile entry points are endpoints with `method = "GET"`; their nature is carried in `protocol`:

| protocol | meaning | example URL |
|---|---|---|
| `mobile-scheme` | custom URL-scheme deep link | `myapp://complex/:id` |
| `android-intent` | exported intent component reachable by intent — a data-less action filter, or no intent-filter at all (explicit-intent only) | `intent://com.example.app/.SyncService` |
| `android-provider` | exported ContentProvider reachable by another app through a `content://authority` URI | `content://com.example.app.provider` |
| `universal-link` | verified Android App Link / iOS universal link, or a server-side `assetlinks.json` / `apple-app-site-association` pattern | `https://app.example.com/complex/:id`, `/buy/*` |

In plain output they render under a `SCHEME` / `INTENT` / `PROVIDER` / `UNIVERSAL` prefix. The handling component, intent action and category, host, and package are stored in a per-endpoint metadata map (serialized in JSON / YAML; omitted entirely for ordinary HTTP endpoints):

```
SCHEME myapp://complex/:id
  ○ via: .DeepLinkActivity
  ○ action: android.intent.action.VIEW
  ○ host: complex
  ○ package: com.example.myapp
```

## Linking to handler code

When the handler source is present in the scan, Noir connects each deep-link endpoint to the code that processes it:

* **Android** — the manifest component (e.g. `.DeepLinkActivity`) is resolved to its `.kt` / `.java` file. The intent-handling methods (`onCreate`, `onNewIntent`, `onReceive`, …) contribute 1-hop callees, and the inputs they read become parameters: `uri.getQueryParameter("q")` → a `query` param (baked into the URL), and the `get*Extra` family → an `extra` param.
* **iOS** — deep links are dispatched centrally, so Noir discovers the handlers and attaches them by kind: `.onOpenURL` / `application(_:open:)` / `scene(_:openURLContexts:)` to custom schemes, and the `userActivity` handlers to universal links. `URLQueryItem` reads become `query` params.

With `--ai-context`, the handler body feeds Noir's source / sink / guard inference, so a deep link that flows into a WebView load or another sink surfaces with the taint path attached.

## Output behavior

Mobile endpoints stay in the structured inventory — JSON, JSONL, YAML, SARIF, Markdown, mermaid, HTML — and in the Elasticsearch / webhook exports, because they are part of the app's surface. They are **excluded** from HTTP-shaped output and delivery — cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, and active probe / proxy delivery — because an app URL is something you open, not an HTTP request you send.

## Notes and limitations

* Source code must be present for handler linkage. A manifest- or plist-only scan still yields the endpoints, just without callees, params, or AI context.
* Binary (compiled) `Info.plist` files are skipped; source-repo XML plists are parsed.
* gradle placeholder resolution reads the nearest `build.gradle(.kts)` above the manifest; when the same placeholder is declared more than once (e.g. a `buildTypes` override), the first declaration — by convention `defaultConfig` — wins. Variant-specific values are not modeled. A placeholder with no gradle value stays verbatim in the URL and the endpoint is tagged `unresolved`.
* Scheme-less Jetpack Navigation URIs (which match both http and https at runtime) are emitted once under `https`. `{arg}` segments become `:arg` path params, `?key={arg}` query placeholders become `query` params, and a trailing `.*` wildcard keeps the literal prefix.
* An `android:exported="true"` component with no intent-filter is reported as an explicit-intent surface (`android-intent`, with `explicit`/`exported`/`component_type` in metadata): an explicit intent naming the component still reaches it even with no action, category, or data URI. A filter-less component that is not exported, or is `android:enabled="false"`, is not reported. A guarding `android:permission` is recorded in metadata but does not suppress the surface — `normal`/`dangerous` permissions remain obtainable by another app.
* An exported `<provider>` (ContentProvider) is reported as an `android-provider` surface — one `content://authority` endpoint per `android:authorities` entry. The provider class links as the handler (`via`), so its `query` / `insert` / `openFile` methods contribute callees (a raw SQL / file sink surfaces in AI context). `android:readPermission` / `android:writePermission` / `android:permission`, `android:grantUriPermissions` (or a `<grant-uri-permission>` child), and the presence of `<path-permission>` overrides ride in metadata — all recorded, never suppressed. Only an explicitly exported provider is reported (a provider defaults to not-exported on modern SDKs); the effective per-path permission of a `<path-permission>` is flagged but not resolved.
* `assetlinks.json` only declares the package association (no paths), so it yields a single `/*` endpoint per app. `apple-app-site-association` paths (`/buy/*`, `NOT /private/*`) and `components` are emitted individually; AASA exclusions are tagged `excluded`.
* Only the plain-JSON form of `apple-app-site-association` is parsed; CMS-signed AASA files (older apps) are skipped.
