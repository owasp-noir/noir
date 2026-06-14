+++
title = "모바일 앱"
description = "Noir가 Android·iOS 딥링크 진입점을 추출하고 이를 처리하는 코드와 연결하는 방식입니다."
weight = 6
sort_by = "weight"

+++

Noir는 모바일 앱이 외부에 노출하는 진입점 — 딥링크와 exported 컴포넌트 — 을 엔드포인트로 추출하고, 이를 처리하는 소스 코드와 연결합니다. 딥링크는 전형적인 모바일 공격 표면입니다. 외부에서 주어진 URL이나 인텐트가 앱 내부로 흘러 들어가 WebView, SQL 쿼리, 다른 컴포넌트에 도달할 수 있기 때문입니다.

## Noir가 파싱하는 대상

| 플랫폼 | 소스 파일 | 추출 내용 |
|---|---|---|
| Android | `AndroidManifest.xml` | 커스텀 URL 스킴 딥링크, exported 인텐트 컴포넌트, exported ContentProvider, 검증된 App Link |
| Android | `res/values/strings.xml` | 스킴·호스트·경로에 쓰인 `@string/` 참조 해석 |
| Android | `build.gradle` / `build.gradle.kts` | 패키지·컴포넌트 이름·스킴·호스트에 쓰인 `${applicationId}`와 커스텀 `manifestPlaceholders` 해석. 매니페스트에 `package` 속성이 없으면 패키지도 여기서 가져옵니다 |
| Android | `res/navigation/*.xml` | Jetpack Navigation `<deepLink app:uri="...">` 딥링크 — 소속 destination이 처리 컴포넌트가 됩니다 |
| iOS | `Info.plist` (`CFBundleURLTypes`를 선언한 모든 `*.plist`) | 커스텀 URL 스킴 — `.xcconfig` / `project.pbxproj`의 `$(VAR)` / `${VAR}` 플레이스홀더도 해석 |
| iOS | `*.entitlements` | `associated-domains`의 `applinks:` 유니버설 링크와 `appclips:` App Clip 실행 URL |
| Android | `/.well-known/assetlinks.json` | 서버 측 App Links 연결 선언(Digital Asset Links) |
| iOS | `apple-app-site-association` | 서버 측 유니버설 링크 `paths` / `components` 패턴 |

앞의 여섯 행은 앱 번들에 선언되는 **클라이언트** 측 연결이고, 마지막 두 행은 **서버** 측 — OS가 해당 호스트의 URL에 대해 앱을 열도록 호스트가 게시하는 well-known 파일 — 입니다. 둘 다 동일한 `universal-link` protocol과 출력 모델을 통해 처리됩니다.

## 엔드포인트 모델

모바일 진입점은 `method = "GET"`인 엔드포인트이며, 그 성격은 `protocol`에 담깁니다.

| protocol | 의미 | 예시 URL |
|---|---|---|
| `mobile-scheme` | 커스텀 URL 스킴 딥링크 | `myapp://complex/:id` |
| `android-intent` | 인텐트로 도달 가능한 exported 컴포넌트 — data URI 없는 action 필터, 또는 intent-filter가 전혀 없는 경우(명시적 인텐트 전용) | `intent://com.example.app/.SyncService` |
| `android-provider` | 다른 앱이 `content://authority` URI로 도달할 수 있는 exported ContentProvider | `content://com.example.app.provider` |
| `universal-link` | 검증된 Android App Link / iOS 유니버설 링크, 또는 서버 측 `assetlinks.json` / `apple-app-site-association` 패턴 | `https://app.example.com/complex/:id`, `/buy/*` |

plain 출력에서는 `SCHEME` / `INTENT` / `PROVIDER` / `UNIVERSAL` 프리픽스로 표시됩니다. 처리 컴포넌트, 인텐트 action·category, 호스트, 패키지는 엔드포인트별 metadata 맵에 저장됩니다(JSON / YAML에 직렬화되며, 일반 HTTP 엔드포인트에서는 완전히 생략됩니다).

```
SCHEME myapp://complex/:id
  ○ via: .DeepLinkActivity
  ○ action: android.intent.action.VIEW
  ○ host: complex
  ○ package: com.example.myapp
```

## 핸들러 코드와의 연결

스캔에 핸들러 소스가 포함되어 있으면, Noir는 각 딥링크 엔드포인트를 이를 처리하는 코드와 연결합니다.

* **Android** — 매니페스트의 컴포넌트(예: `.DeepLinkActivity`)를 해당 `.kt` / `.java` 파일로 해석합니다. 인텐트 처리 메서드(`onCreate`, `onNewIntent`, `onReceive`, …)에서 1-hop callee를 수집하고, 그 안에서 읽는 입력을 파라미터로 만듭니다. `uri.getQueryParameter("q")` → `query` 파라미터(URL에 baking), `get*Extra` 계열 → `extra` 파라미터.
* **iOS** — 딥링크는 중앙에서 디스패치되므로, Noir는 핸들러를 탐색해 종류별로 연결합니다. `.onOpenURL` / `application(_:open:)` / `scene(_:openURLContexts:)`는 커스텀 스킴에, `userActivity` 핸들러는 유니버설 링크에 붙입니다. `URLQueryItem` 읽기는 `query` 파라미터가 됩니다.

`--ai-context`를 사용하면 핸들러 본문이 Noir의 source / sink / guard 추론에 입력되어, WebView 로드 같은 싱크로 흘러가는 딥링크가 taint 경로와 함께 드러납니다.

## 출력 동작

모바일 엔드포인트는 구조화된 인벤토리(JSON, JSONL, YAML, SARIF, Markdown, mermaid, HTML)와 Elasticsearch / webhook export에는 그대로 포함됩니다 — 앱 표면의 일부이기 때문입니다. 반면 HTTP 모양을 가정하는 출력·전송 — cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, 능동 프로빙 / 프록시 전송 — 에서는 **제외**됩니다. 앱 URL은 보내는 HTTP 요청이 아니라 여는 대상이기 때문입니다.

## 참고 및 한계

* 핸들러 연결에는 소스 코드가 필요합니다. 매니페스트·plist만 있는 스캔도 엔드포인트는 추출하지만 callee·파라미터·AI 컨텍스트는 붙지 않습니다.
* 바이너리(컴파일된) `Info.plist`는 건너뜁니다. 소스 저장소의 XML plist는 파싱합니다.
* gradle 플레이스홀더는 매니페스트 위쪽에서 가장 가까운 `build.gradle(.kts)`를 읽어 해석합니다. 같은 플레이스홀더가 여러 번 선언되면(예: `buildTypes` 오버라이드) 먼저 선언된 쪽 — 관례상 `defaultConfig` — 이 우선하며, 빌드 variant별 값은 모델링하지 않습니다. gradle에 값이 없는 플레이스홀더는 URL에 그대로 남고 엔드포인트에 `unresolved` 태그가 붙습니다.
* 스킴 없는 Jetpack Navigation URI(런타임에는 http·https 모두 매칭)는 `https` 하나로 추출합니다. `{arg}` 세그먼트는 `:arg` path 파라미터로, `?key={arg}` 쿼리 플레이스홀더는 `query` 파라미터로 바뀌고, 끝의 `.*` 와일드카드는 리터럴 프리픽스만 남깁니다.
* intent-filter가 없는 `android:exported="true"` 컴포넌트는 명시적 인텐트 표면(`android-intent`, metadata에 `explicit`/`exported`/`component_type` 포함)으로 보고됩니다. action·category·data URI가 없어도, 컴포넌트 이름을 지정한 명시적 인텐트는 여전히 그 컴포넌트에 도달합니다. exported가 아니거나 `android:enabled="false"`인 필터 없는 컴포넌트는 보고하지 않습니다. 보호용 `android:permission`은 metadata에 기록되지만 표면을 숨기지는 않습니다 — `normal`/`dangerous` 권한은 다른 앱이 여전히 획득할 수 있기 때문입니다.
* exported `<provider>`(ContentProvider)는 `android-provider` 표면으로 보고됩니다 — `android:authorities` 항목마다 `content://authority` 엔드포인트 하나씩. provider 클래스가 핸들러(`via`)로 연결되므로 `query` / `insert` / `openFile` 메서드의 callee가 수집되어, raw SQL·파일 싱크가 AI 컨텍스트에 드러납니다. `android:readPermission` / `android:writePermission` / `android:permission`, `android:grantUriPermissions`(또는 `<grant-uri-permission>` 자식), 그리고 `<path-permission>` 오버라이드의 존재 여부가 metadata에 실립니다 — 모두 기록만 하고 숨기지 않습니다. 명시적으로 exported된 provider만 보고합니다(최신 SDK에서 provider 기본값은 not-exported). `<path-permission>`의 경로별 실효 권한은 표시만 하고 해석하지는 않습니다.
* `assetlinks.json`은 패키지 연결만 선언하고 경로는 없으므로 앱당 `/*` 엔드포인트 하나를 만듭니다. `apple-app-site-association`의 경로(`/buy/*`, `NOT /private/*`)와 `components`는 개별적으로 추출되며, AASA 제외 패턴은 `excluded` 태그가 붙습니다.
* `apple-app-site-association`은 plain-JSON 형식만 파싱합니다. CMS로 서명된 AASA 파일(구형 앱)은 건너뜁니다.
