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
| Android | `AndroidManifest.xml` | 커스텀 URL 스킴 딥링크, exported 인텐트 컴포넌트, 검증된 App Link |
| Android | `res/values/strings.xml` | 스킴·호스트·경로에 쓰인 `@string/` 참조 해석 |
| iOS | `Info.plist` | `CFBundleURLTypes` 커스텀 URL 스킴 |
| iOS | `*.entitlements` | `associated-domains`의 `applinks:` 유니버설 링크 |

## 엔드포인트 모델

모바일 진입점은 `method = "GET"`인 엔드포인트이며, 그 성격은 `protocol`에 담깁니다.

| protocol | 의미 | 예시 URL |
|---|---|---|
| `mobile-scheme` | 커스텀 URL 스킴 딥링크 | `myapp://complex/:id` |
| `android-intent` | data URI 없는 exported 인텐트 컴포넌트 | `intent://com.example.app/.SyncService` |
| `universal-link` | 검증된 Android App Link / iOS 유니버설 링크 | `https://app.example.com/complex/:id` |

plain 출력에서는 `SCHEME` / `INTENT` / `UNIVERSAL` 프리픽스로 표시됩니다. 처리 컴포넌트, 인텐트 action·category, 호스트, 패키지는 엔드포인트별 metadata 맵에 저장됩니다(JSON / YAML에 직렬화되며, 일반 HTTP 엔드포인트에서는 완전히 생략됩니다).

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
* gradle `${applicationId}` 플레이스홀더와 Jetpack Navigation 딥링크는 아직 해석하지 않습니다.
