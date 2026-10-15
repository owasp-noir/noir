+++
title = "모바일 앱"
description = "Noir가 Android·iOS 딥링크 진입점을 추출하고 이를 처리하는 코드와 연결하는 방식입니다."
weight = 6
sort_by = "weight"

+++

Noir는 Android나 iOS 앱의 진입점을 엔드포인트로 보고합니다. 진입점이란 앱이 외부에 노출하는 딥링크와 exported 컴포넌트입니다. Noir는 각 진입점을 그것을 처리하는 소스 코드와도 연결합니다.

딥링크는 전형적인 모바일 공격 표면입니다. 외부에서 주어진 URL이나 인텐트가 앱 안으로 흘러 들어가 WebView, SQL 쿼리, 다른 컴포넌트에 도달할 수 있습니다.

별도 플래그는 없습니다. 평소처럼 앱 소스 트리를 스캔하면 Noir가 아래 파일들을 읽습니다:

```bash
noir scan path/to/app
```

## Noir가 파싱하는 대상

| 플랫폼 | 소스 파일 | 추출 내용 |
|---|---|---|
| Android | `AndroidManifest.xml` | 커스텀 URL 스킴 딥링크, exported 인텐트 컴포넌트, exported ContentProvider, 검증된 App Link |
| Android | `res/values/strings.xml` | 스킴·호스트·경로에 쓰인 `@string/` 참조 해석 |
| Android | `build.gradle` / `build.gradle.kts` | 패키지·컴포넌트 이름·스킴·호스트에 쓰인 `${applicationId}`와 커스텀 `manifestPlaceholders` 해석. 매니페스트에 `package` 속성이 없으면 패키지도 여기서 가져옵니다 |
| Android | `res/navigation/*.xml` | Jetpack Navigation `<deepLink app:uri="...">` 딥링크. 소속 destination이 처리 컴포넌트가 됩니다 |
| iOS | `Info.plist` (`CFBundleURLTypes`를 선언한 모든 `*.plist`) | 커스텀 URL 스킴. `.xcconfig` / `project.pbxproj`의 `$(VAR)` / `${VAR}` 플레이스홀더도 해석 |
| iOS | `*.entitlements` | `associated-domains`의 `applinks:` 유니버설 링크와 `appclips:` App Clip 실행 URL |
| Android | `/.well-known/assetlinks.json` | 서버 측 App Links 연결 선언(Digital Asset Links) |
| iOS | `apple-app-site-association` | 서버 측 유니버설 링크 `paths` / `components` 패턴 |

앞의 여섯 행은 앱 번들에 선언되는 **클라이언트** 측입니다. 마지막 두 행은 **서버** 측으로, 호스트가 자기 URL을 OS가 앱으로 열도록 게시하는 well-known 파일입니다. 이 연결의 양쪽 모두 같은 출력 모델의 `universal-link` 엔드포인트를 만듭니다.

## 엔드포인트 모델

모든 모바일 진입점은 `method = "GET"`인 엔드포인트입니다. 어떤 종류의 진입점인지는 `protocol` 필드가 알려 줍니다:

| protocol | 의미 | 예시 URL |
|---|---|---|
| `mobile-scheme` | 커스텀 URL 스킴 딥링크 | `myapp://complex/:id` |
| `android-intent` | 인텐트로 도달 가능한 exported 컴포넌트: data URI 없는 action 필터, 또는 intent-filter가 전혀 없는 경우(명시적 인텐트 전용) | `intent://com.example.app/.SyncService` |
| `android-provider` | 다른 앱이 `content://authority` URI로 도달할 수 있는 exported ContentProvider | `content://com.example.app.provider` |
| `universal-link` | 검증된 Android App Link / iOS 유니버설 링크, 또는 서버 측 `assetlinks.json` / `apple-app-site-association` 패턴 | `https://app.example.com/complex/:id`, `/buy/*` |

plain 출력에서는 종류마다 `SCHEME`, `INTENT`, `PROVIDER`, `UNIVERSAL` 프리픽스가 붙습니다.

처리 컴포넌트, 인텐트 action·category, 호스트, 패키지는 엔드포인트별 metadata 맵에 들어갑니다. JSON과 YAML 출력에 포함되며, 일반 HTTP 엔드포인트에는 이 맵이 없습니다.

```
SCHEME myapp://complex/:id
  ○ path: id
  ○ via: .DeepLinkActivity
  ○ action: android.intent.action.VIEW
  ○ category: android.intent.category.DEFAULT
  ○ host: complex
  ○ package: com.example.myapp
```

## 핸들러 코드와의 연결

스캔 대상에 핸들러 소스가 있으면 Noir는 각 딥링크 엔드포인트를 그것을 처리하는 코드와 연결합니다.

**Android**

* 매니페스트의 컴포넌트(예: `.DeepLinkActivity`)를 해당 `.kt` / `.java` 파일로 해석합니다.
* 인텐트 처리 메서드(`onCreate`, `onNewIntent`, `onReceive`, …)에서 1-hop callee, 즉 그 메서드가 직접 호출하는 함수를 수집합니다.
* 그 안에서 읽는 입력은 파라미터가 됩니다. `uri.getQueryParameter("q")` → `query` 파라미터(URL에 포함), `get*Extra` 계열 → `extra` 파라미터.

**iOS**

딥링크는 중앙에서 디스패치되므로, Noir는 핸들러를 탐색해 종류별로 연결합니다:

* `.onOpenURL` / `application(_:open:)` / `scene(_:openURLContexts:)` → 커스텀 스킴.
* `userActivity` 핸들러 → 유니버설 링크.
* `URLQueryItem` 읽기는 `query` 파라미터가 됩니다.

`--ai-context`를 사용하면 핸들러 본문이 Noir의 source / sink / guard 추론에 쓰입니다. 그러면 WebView 로드 같은 싱크로 흘러가는 딥링크가 taint 경로(입력이 그 싱크까지 가는 길)와 함께 드러납니다.

## 출력 동작

| 출력 | 모바일 엔드포인트 |
|---|---|
| 구조화된 인벤토리(JSON, JSONL, YAML, TOML, SARIF, Markdown table, mermaid, HTML)와 Elasticsearch / webhook export | 포함합니다. 앱 표면의 일부이기 때문입니다 |
| HTTP 모양을 가정하는 출력·전송(cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, Postman, 능동 프로빙 / 프록시 전송) | 뺍니다. 앱 URL은 보내는 HTTP 요청이 아니라 여는 대상입니다 |
| `-f adb`(Android)와 `-f simctl`(iOS) | 바로 실행 가능한 기기 명령으로 만들어 진입점을 엽니다 |

## 참고 및 한계

**공통**

* 핸들러 연결에는 소스 코드가 필요합니다. 매니페스트·plist만 있는 스캔도 엔드포인트는 추출하지만 callee·파라미터·AI 컨텍스트는 붙지 않습니다.

**Android**

* **gradle 플레이스홀더**: 매니페스트 위쪽에서 가장 가까운 `build.gradle(.kts)`를 읽습니다. 같은 플레이스홀더가 여러 번 선언되면(예: `buildTypes` 오버라이드) 먼저 선언된 쪽(관례상 `defaultConfig`)이 우선합니다. 빌드 variant별 값은 모델링하지 않습니다. gradle에 값이 없는 플레이스홀더는 URL에 그대로 남고, 엔드포인트에 `unresolved` 태그가 붙습니다.
* **Jetpack Navigation**: 스킴 없는 URI(런타임에는 http·https 모두 매칭)는 `https` 하나로 추출합니다. `{arg}` 세그먼트는 `:arg` path 파라미터로, `?key={arg}` 쿼리 플레이스홀더는 `query` 파라미터로 바뀌고, 끝의 `.*` 와일드카드는 리터럴 프리픽스만 남깁니다.
* **intent-filter가 없는 컴포넌트**: intent-filter가 없는 `android:exported="true"` 컴포넌트는 명시적 인텐트 표면(`android-intent`, metadata에 `explicit`/`exported`/`component_type` 포함)으로 보고됩니다. action·category·data URI가 없어도, 컴포넌트 이름을 지정한 명시적 인텐트는 여전히 그 컴포넌트에 도달합니다.
  * exported가 아니거나 `android:enabled="false"`인 필터 없는 컴포넌트는 보고하지 않습니다.
  * 보호용 `android:permission`은 metadata에 기록되지만 표면을 숨기지는 않습니다. `normal`/`dangerous` 권한은 다른 앱이 여전히 획득할 수 있기 때문입니다.
* **ContentProvider**: exported `<provider>`는 `android-provider` 표면으로 보고되며, `android:authorities` 항목마다 `content://authority` 엔드포인트를 하나씩 만듭니다.
  * provider 클래스가 핸들러(`via`)로 연결되므로 `query` / `insert` / `openFile` 메서드의 callee가 수집됩니다. raw SQL·파일 싱크는 AI 컨텍스트에 드러납니다.
  * 권한은 metadata에 기록만 하고 표면을 숨기지 않습니다: `android:readPermission` / `android:writePermission` / `android:permission`, `android:grantUriPermissions`(또는 `<grant-uri-permission>` 자식), 그리고 `<path-permission>` 오버라이드의 존재 여부.
  * 명시적으로 exported된 provider만 보고합니다(최신 SDK에서 provider 기본값은 not-exported).
  * `<path-permission>`의 경로별 실효 권한은 표시만 하고 해석하지는 않습니다.

**iOS**

* 바이너리(컴파일된) `Info.plist`는 건너뜁니다. 소스 저장소의 XML plist는 파싱합니다.
* 앱 자체 스킴에 대해 Swift 코드에 적힌 라우트도 찾습니다. `url.host == SomeEnum.case.rawValue`처럼 비교하는 라우터 enum(각 case가 라우트가 됨)과 하드코딩된 `scheme://host/path` 문자열 리터럴입니다.

**서버 측 연결 파일**

* `assetlinks.json`은 패키지 연결만 선언하고 경로는 없으므로 앱당 `/*` 엔드포인트 하나를 만듭니다.
* `apple-app-site-association`(AASA)의 경로(`/buy/*`, `NOT /private/*`)와 `components`는 개별적으로 추출되며, AASA 제외 패턴에는 `excluded` 태그가 붙습니다.
* AASA는 plain-JSON 형식만 파싱합니다. CMS로 서명된 AASA 파일(구형 앱)은 건너뜁니다.
