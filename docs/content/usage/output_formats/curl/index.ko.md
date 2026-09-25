+++
title = "HTTP 클라이언트 명령어"
description = "Noir 스캔 결과에서 cURL, HTTPie, PowerShell 명령어를 생성합니다."
weight = 1
sort_by = "weight"

+++

발견된 엔드포인트를 바로 실행할 수 있는 HTTP 클라이언트 명령어로 변환합니다. `-u`로 base URL을 지정하면 경로 앞에 자동으로 붙여줍니다.

## cURL

[cURL](https://curl.se/)은 가장 널리 쓰이는 커맨드라인 HTTP 클라이언트입니다. 생성되는 명령어에는 `-i`(응답 헤더 포함), `-X`(HTTP 메서드), `--data-raw`(urlencoded 또는 JSON 바디, 해당 `Content-Type` 헤더와 함께), `-F`(multipart 업로드), `-H`(헤더), `--cookie`(쿠키) 등의 플래그가 적절히 들어갑니다.

```bash
noir scan . -f curl -u https://www.example.com
```

출력 예시
```bash
curl -i -X 'GET' 'https://www.example.com/' -H 'x-api-key: '
curl -i -X 'POST' 'https://www.example.com/query' --data-raw 'query=' -H 'Content-Type: application/x-www-form-urlencoded' --cookie 'my_auth='
curl -i -X 'GET' 'https://www.example.com/token' --data-raw 'client_id=&redirect_url=&grant_type=' -H 'Content-Type: application/x-www-form-urlencoded'
```

## HTTPie

[HTTPie](https://httpie.io/)는 cURL보다 직관적인 문법에 컬러 출력과 JSON 지원이 기본 내장된 HTTP 클라이언트입니다.

```bash
noir scan . -f httpie -u https://www.example.com
```

출력 예시
```bash
http 'GET' 'https://www.example.com/' 'x-api-key: '
http --form 'POST' 'https://www.example.com/query' 'query=' 'Cookie:my_auth='
http --form 'GET' 'https://www.example.com/token' 'client_id=' 'redirect_url=' 'grant_type='
```

## PowerShell

Windows 환경이라면 별도 도구 설치 없이 바로 쓸 수 있는 [Invoke-WebRequest](https://learn.microsoft.com/ko-kr/powershell/module/microsoft.powershell.utility/invoke-webrequest) 명령어를 생성합니다.

```bash
noir scan . -f powershell -u https://www.example.com
```

출력 예시
```powershell
Invoke-WebRequest -Method "GET" -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method "POST" -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method "GET" -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```


## 파일 업로드 (multipart)

엔드포인트에 `param_type: file` 필드(코드에서 발견한 multipart 업로드)가 있으면, HTTP 클라이언트 포맷은 urlencoded/`--data-raw`/`-Body` 형태 대신 multipart로 바뀌어 파일 파트가 빠지지 않습니다.

| 포맷 | 형태 |
|------|------|
| cURL (`-f curl`) | 형제 form 필드는 `-F 'field=value'`, 각 파일은 `-F 'avatar=@avatar'` (경로 힌트가 비어 있으면 필드 이름을 `@filename`으로 사용) |
| HTTPie (`-f httpie`) | `--form` 과 함께 `field=value`, `avatar@avatar` |
| PowerShell (`-f powershell`) | `-Form @{ "field"="…"; "avatar"=Get-Item -Path "avatar" }` (multipart `Content-Type`은 PowerShell이 설정) |

예시 (`title` form 필드와 `avatar` 파일 필드가 있는 `POST /upload`):

```bash
# cURL
curl -i -X 'POST' 'https://www.example.com/upload' -F 'title=' -F 'avatar=@avatar'

# HTTPie
http --form 'POST' 'https://www.example.com/upload' 'title=' 'avatar@avatar'

# PowerShell
Invoke-WebRequest -Method "POST" -Uri "https://www.example.com/upload" -Form @{"title"=""; "avatar"=Get-Item -Path "avatar"}
```

필드 이름 placeholder 대신 실제 경로를 쓰려면 `--pvalue`로 `@filename` / `Get-Item` 경로를 채우면 됩니다 (예: `--pvalue "any=avatar=./fixture.png"`). 파일 필드가 없으면 위 urlencoded 예시 형태가 그대로 유지됩니다.

## XML 요청 본문

`param_type: xml`(Play `asXml`, Tapir `xmlBody` 등 전체 본문 XML 파라미터)은 HTTP 클라이언트 형식(`curl`, `httpie`, `powershell`)에서 요청 본문으로 내려가지 **않습니다**. 이 빌더들은 `form` / `json` 본문과 위의 multipart `file` 업로드만 구성합니다. XML 본문 파라미터만 있는 엔드포인트는 이 형식들에서 헤더/URL 만 있는 명령으로 출력됩니다.

XML 본문이 필요하면 다음을 사용하세요.

- `-f oas2` / `-f oas3` — `application/xml` requestBody ([OpenAPI](@/usage/output_formats/openapi/index.ko.md) 참고)
- `-f postman` — `Content-Type: application/xml` 인 raw 본문 ([추가 형식](@/usage/output_formats/more/index.ko.md#postman-collection) 참고)
- `-f json` / `-f yaml` / plain — 엔드포인트 기록에 `xml` 파라미터 타입이 그대로 유지됨

HTML 리포트의 "curl로 복사" 버튼도 같은 curl 빌더를 쓰므로 동일한 제약이 있습니다.

## ADB (Android)

모바일 진입점은 HTTP 요청이 아니라 앱 URL이므로 위의 HTTP 클라이언트들은 이를 건너뜁니다. `-f adb` 는 그 반대로 동작합니다. Noir가 찾아낸 Android 딥링크, 인텐트 컴포넌트, 콘텐츠 프로바이더를 연결된 기기나 에뮬레이터에서 바로 실행할 수 있는 [Android Debug Bridge](https://developer.android.com/tools/adb) 명령어로 변환합니다.

`adb` 는 Android 전용이므로, Android 출처 진입점만 명령어로 만들고 실행할 수 없는 나머지(HTTP 엔드포인트, iOS 스킴은 [`-f simctl`](#simctl-ios) 사용, 도메인만 선언하는 App Links)는 건너뜁니다. 건너뛴 항목은 종류별로 한 줄씩 stderr 경고로 알려줍니다(덕분에 stdout 명령어 목록은 파이프로 넘기기 좋게 유지됨).

```bash
noir scan ./my-android-app -f adb
```

출력 예시
```bash
# 커스텀 스킴 딥링크 / 검증된 앱 링크 → VIEW 인텐트로 am start
adb shell am start -a 'android.intent.action.VIEW' -c 'android.intent.category.BROWSABLE' -d 'myapp://host/path' -p 'com.example.app'
# 명시적 액티비티 / 서비스 / 리시버 → am start / startservice / broadcast
adb shell am start -n 'com.example.app/.ExportedActivity'
adb shell am startservice -n 'com.example.app/.SyncService'
adb shell am broadcast -n 'com.example.app/.BootReceiver'
# 익스포트된 ContentProvider → content query
adb shell content query --uri 'content://com.example.app.provider'
```

액션, 카테고리, 패키지는 매니페스트의 intent-filter에서 가져오므로 각 실행 명령이 선언된 필터와 일치합니다. 핸들러에서 발견된 인텐트 extra는 `--es` 문자열 extra로 출력됩니다(빈 템플릿으로 두거나 `--pvalue` 로 값을 채울 수 있습니다). 이 진입점들이 어떻게 추출되는지는 [Mobile Apps](../../supported/mobile/) 문서를 참고하세요.

## simctl (iOS)

`-f simctl` 은 `-f adb` 의 iOS 짝입니다. Noir가 찾아낸 iOS 커스텀 스킴 딥링크와 유니버설 링크를 부팅된 iOS 시뮬레이터에서 열 수 있는 [`xcrun simctl openurl`](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) 명령어로 변환합니다. iOS에는 인텐트나 콘텐츠 프로바이더에 해당하는 개념이 없어, 모든 명령은 단일 `openurl` 입니다.

```bash
noir scan ./my-ios-app -f simctl
```

출력 예시
```bash
xcrun simctl openurl booted 'myapp://host/path?token='
xcrun simctl openurl booted 'https://app.example.com/buy'
```

`-f adb` 와 마찬가지로 `simctl` 도 플랫폼 전용입니다. iOS 출처 진입점만 명령어로 만들고 열 수 없는 나머지(HTTP 엔드포인트, Android 진입점은 `-f adb` 사용, 도메인만 선언하는 App Links)는 건너뛰며, 종류별로 한 줄씩 stderr 경고로 알려줍니다.

## 파라미터 값 채우기

Noir는 기본적으로 파라미터 값을 비워두기 때문에(`x-api-key=`, `query=` …) 생성된 명령은 템플릿처럼 동작합니다. 그대로 실행하거나 퍼징 입력 시드를 만들고 싶다면 `--pvalue` 로 값을 미리 채울 수 있습니다.

```
--pvalue TYPE=VALUE     # 반복 가능
```

| `TYPE`            | 적용 범위                                              |
|-------------------|-------------------------------------------------------|
| `any` (생략 가능) | 모든 파라미터 타입                                     |
| `query`           | 쿼리 스트링                                            |
| `form`            | 폼 바디 (`application/x-www-form-urlencoded`)          |
| `json`            | JSON 바디                                              |
| `header`          | 요청 헤더                                              |
| `cookie`          | 쿠키                                                  |
| `path`            | 경로 파라미터                                          |

`VALUE`는 두 가지 형태를 받습니다.

| 형태                                  | 동작                                                |
|--------------------------------------|----------------------------------------------------|
| `<value>`                            | 대상 타입의 모든 파라미터에 사용                     |
| `<name>=<value>` 또는 `<name>:<value>` | 이름이 `<name>`인 파라미터에만 사용                 |

`--pvalue` 는 반복 사용 가능하며, 동일 파라미터에 매치되면 타입별 규칙이 일반 `any` 스코프보다 우선합니다.

```bash
# 모든 파라미터를 `test`로 채움
noir scan . -f curl -u https://example.com --pvalue "test"

# `Authorization` 헤더와 `id` 경로 파라미터에만 값 채움
noir scan . -f curl -u https://example.com \
  --pvalue "header=Authorization=Bearer xyz" \
  --pvalue "path=id=42"

# 쿼리는 기본 `1`이지만 `limit`은 항상 10
noir scan . -f curl -u https://example.com \
  --pvalue "query=1" \
  --pvalue "query=limit=10"
```

같은 플래그는 HTTPie와 PowerShell 출력에도 적용되며, OpenAPI / Postman / JSON 등 값이 렌더링되는 다른 형식에도 전파됩니다.

> **레거시:** v0 의 `--set-pvalue`, `--set-pvalue-query`, `--set-pvalue-header`
> 등은 v1.x 에서 silent alias 로 그대로 동작합니다. 새 스크립트는 위의 통합된
> `--pvalue TYPE=VALUE` 를 우선 사용하세요.
