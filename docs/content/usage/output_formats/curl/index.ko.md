+++
title = "HTTP 클라이언트 명령"
description = "Noir 스캔 결과에서 cURL, HTTPie, PowerShell 명령을 생성합니다."
weight = 1
sort_by = "weight"

+++

발견한 엔드포인트를 바로 실행할 수 있는 HTTP 클라이언트 명령으로 바꿉니다. `-u`로 base URL을 지정하면 각 경로 앞에 붙습니다. `-u`가 없으면 명령은 경로만 대상으로 합니다(`'/query'`).

## cURL

[cURL](https://curl.se/)은 가장 널리 쓰이는 커맨드라인 HTTP 클라이언트입니다. 생성되는 명령에는 `-i`(응답 헤더 표시), `-g`(URL globbing을 꺼서 `{id}`, `[..]`를 그대로 보냄), `-X`(HTTP 메서드, HEAD는 대신 `-I`), `--data-raw`(urlencoded 또는 JSON 본문, 맞는 `Content-Type` 헤더와 함께), `--form-string`과 `-F`(multipart 업로드), `-H`(헤더, 값이 빈 헤더는 `'Name;'`로 출력), `--cookie`(쿠키)가 필요에 따라 들어갑니다.

```bash
noir scan . -f curl -u https://www.example.com
```

출력 예시
```bash
curl -i -g -X 'GET' 'https://www.example.com/' -H 'x-api-key;'
curl -i -g -X 'POST' 'https://www.example.com/query' --data-raw 'query=' -H 'Content-Type: application/x-www-form-urlencoded' --cookie 'my_auth='
curl -i -g -X 'GET' 'https://www.example.com/token' --data-raw 'client_id=&redirect_url=&grant_type=' -H 'Content-Type: application/x-www-form-urlencoded'
```

## HTTPie

[HTTPie](https://httpie.io/)는 cURL보다 문법이 짧은 커맨드라인 HTTP 클라이언트입니다.

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

Windows용입니다. 별도 도구 없이 쓸 수 있는 [Invoke-WebRequest](https://learn.microsoft.com/ko-kr/powershell/module/microsoft.powershell.utility/invoke-webrequest) 명령을 생성합니다.

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

엔드포인트에 `param_type: file` 필드(코드에서 찾은 multipart 업로드)가 있으면, HTTP 클라이언트 형식은 urlencoded(`--data-raw` / `-Body`) 대신 multipart로 바뀝니다. 그래야 파일 파트가 빠지지 않습니다.

| 형식 | 형태 |
|------|------|
| cURL (`-f curl`) | 나머지 form 필드는 `--form-string 'field=value'`(값을 그대로 보내므로 `@`나 `<`로 시작하는 값도 파일로 읽지 않음), 각 파일은 `-F 'avatar=@avatar'` |
| HTTPie (`-f httpie`) | `--form`과 함께 `field=value`, `avatar@avatar` |
| PowerShell (`-f powershell`) | `-Form @{ "field"="…"; "avatar"=Get-Item -Path "avatar" }` (multipart `Content-Type`은 PowerShell이 설정) |

예시 (`title` form 필드와 `avatar` 파일 필드가 있는 `POST /upload`):

```bash
# cURL
curl -i -g -X 'POST' 'https://www.example.com/upload' --form-string 'title=' -F 'avatar=@avatar'

# HTTPie
http --form 'POST' 'https://www.example.com/upload' 'title=' 'avatar@avatar'

# PowerShell
Invoke-WebRequest -Method "POST" -Uri "https://www.example.com/upload" -Form @{"title"=""; "avatar"=Get-Item -Path "avatar"}
```

파일 경로는 필드 이름을 딴 자리표시자입니다. `--pvalue`는 파일 필드를 채우지 않으니 경로는 직접 바꾸세요. 파일 필드가 없으면 위의 urlencoded 예시 형태 그대로 나옵니다.

## XML 요청 본문

`param_type: xml`(Play `asXml`, Tapir `xmlBody` 등 전체 본문 XML 파라미터)은 HTTP 클라이언트 형식(`curl`, `httpie`, `powershell`)에서 요청 본문으로 들어가지 않습니다. 이 빌더들은 `form` / `json` 본문과 위의 multipart `file` 업로드만 구성합니다. 그래서 XML 본문 파라미터만 있는 엔드포인트는 이 형식들에서 헤더와 URL만 있는 명령으로 나옵니다.

XML 본문이 필요하면 다음을 사용하세요.

- `-f oas2` / `-f oas3`: `application/xml` requestBody ([OpenAPI](@/usage/output_formats/openapi/index.ko.md) 참고)
- `-f postman`: `Content-Type: application/xml` 인 raw 본문 ([추가 형식](@/usage/output_formats/more/index.ko.md) 참고)
- `-f json` / `-f yaml` / plain: 엔드포인트 기록에 `xml` 파라미터 타입이 그대로 유지됨

HTML 리포트의 "curl로 복사" 버튼도 같은 curl 빌더를 쓰므로 동일한 제약이 있습니다.

## ADB (Android)

모바일 진입점은 HTTP 요청이 아니라 앱 URL이므로 위의 HTTP 클라이언트들은 이를 건너뜁니다. `-f adb`는 반대로 이것만 다룹니다. Noir가 찾아낸 Android 딥링크, 인텐트 컴포넌트, 콘텐츠 프로바이더를 연결된 기기나 에뮬레이터에서 바로 실행할 수 있는 [Android Debug Bridge](https://developer.android.com/tools/adb) 명령으로 변환합니다.

`adb`는 Android 전용입니다. Android 진입점만 명령으로 만들고, 실행할 수 없는 나머지(HTTP 엔드포인트, iOS 스킴은 [`-f simctl`](#simctl-ios) 사용, 도메인만 선언하는 App Links)는 건너뜁니다. 건너뛴 종류마다 stderr에 경고가 한 줄씩 나오므로 stdout은 파이프로 넘기기 깔끔합니다.

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

액션, 카테고리, 패키지는 매니페스트의 intent-filter에서 가져오므로 각 실행 명령이 선언된 필터와 일치합니다. 핸들러에서 찾은 인텐트 extra는 값이 빈 `--es` 문자열 extra로 출력되니 직접 채우세요(`--pvalue`는 여기에 적용되지 않습니다). 진입점을 어떻게 추출하는지는 [Mobile Apps](../../supported/mobile/) 문서를 참고하세요.

## simctl (iOS)

`-f simctl`은 `-f adb`의 iOS 버전입니다. Noir가 찾아낸 iOS 커스텀 스킴 딥링크와 유니버설 링크를 부팅된 iOS 시뮬레이터에서 열 수 있는 [`xcrun simctl openurl`](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) 명령으로 변환합니다. iOS에는 인텐트나 콘텐츠 프로바이더에 해당하는 개념이 없어, 모든 명령은 단일 `openurl`입니다.

```bash
noir scan ./my-ios-app -f simctl
```

출력 예시
```bash
xcrun simctl openurl booted 'myapp://host/path?token='
xcrun simctl openurl booted 'https://app.example.com/buy'
```

`-f adb`와 마찬가지로 `simctl`도 플랫폼 전용입니다. iOS 진입점만 명령으로 만들고 열 수 없는 나머지(HTTP 엔드포인트, Android 진입점은 `-f adb` 사용, 도메인만 선언하는 App Links)는 건너뛰며, 종류별로 한 줄씩 stderr 경고로 알려줍니다.

## 파라미터 값 채우기

Noir는 기본적으로 파라미터 값을 비워두기 때문에(`x-api-key=`, `query=` …) 생성된 명령은 템플릿처럼 동작합니다. 그대로 실행할 스크립트나 퍼징 시드가 필요하면 `--pvalue`로 값을 채우세요.

```
--pvalue TYPE=VALUE     # 반복 가능
```

| `TYPE`            | 적용 범위                                              |
|-------------------|-------------------------------------------------------|
| `any` (값에 `=`가 없으면 `TYPE=` 생략 가능) | `file`, `xml`을 뺀 모든 파라미터 타입 |
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
| `<name>=<value>` 또는 `<name>:<value>` | 이름이 `<name>`인 파라미터에만 사용. `TYPE=`을 반드시 붙여야 함(`any=`도 가능) |

`--pvalue`는 여러 번 쓸 수 있습니다. 파라미터 이름을 지정한 규칙이 타입 전체 값보다 우선하고, 같은 종류끼리는 타입별 규칙이 `any` 규칙보다 우선합니다.

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

같은 값이 HTTPie와 PowerShell 출력에도, 파라미터 값을 출력하는 다른 형식(OpenAPI, Postman, JSON 등)에도 그대로 들어갑니다.

> 레거시: v0의 `--set-pvalue`, `--set-pvalue-query`, `--set-pvalue-header` 등은
> v1.x에서도 경고 없이 별칭으로 동작합니다. 새 스크립트에는 위의
> `--pvalue TYPE=VALUE`를 쓰세요.
