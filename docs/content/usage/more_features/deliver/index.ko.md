+++
title = "다른 도구로 결과 전송하기"
description = "Noir의 'Deliver' 기능을 사용하여 발견된 엔드포인트를 Burp Suite, ZAP 또는 Elasticsearch와 같은 다른 도구로 전송하여 추가 분석 및 보안 테스트를 수행하는 방법을 알아보세요."
weight = 1
sort_by = "weight"

[extra]
+++

Noir의 "Deliver" 기능은 코드 분석을 보안 워크플로의 다른 도구와 통합하는 강력한 방법입니다. 결과를 터미널에서만 보는 대신 발견된 엔드포인트를 Burp Suite나 ZAP와 같은 프록시 도구나 Elasticsearch와 같은 데이터 분석 플랫폼으로 직접 전송할 수 있습니다.

이렇게 하면 코드 분석에서 활성 보안 테스트로 이동하거나 시간이 지나면서 발견한 내용을 저장하고 분석하는 것이 훨씬 쉬워집니다.

## Deliver 기능 사용 방법

Deliver 기능은 다음 명령줄 플래그로 제어됩니다:

*   `--send-req`: 결과를 웹 요청으로 전송합니다.
*   `--send-proxy http://proxy...`: HTTP 프록시를 통해 결과를 전송합니다.
*   `--send-es http://es...`: Elasticsearch 인스턴스로 결과를 전송합니다.
*   `--with-headers X-Header:Value`: 요청에 사용자 정의 헤더를 추가합니다.
*   `--use-matchers string`: 특정 패턴(URL, 메서드 또는 메서드:URL 조합)과 일치하는 엔드포인트만 전송합니다.
*   `--use-filters string`: 특정 패턴(URL, 메서드 또는 메서드:URL 조합)과 일치하는 엔드포인트를 제외합니다.

### 프록시로 전송

`http://localhost:8080`에서 실행 중인 Burp Suite나 ZAP와 같은 프록시로 발견된 모든 엔드포인트를 전송하려면 `--send-proxy` 플래그를 사용합니다:

```bash
noir -b ./source --send-proxy http://localhost:8080
```

이렇게 하면 Noir가 찾은 모든 엔드포인트로 프록시의 히스토리를 채워서 즉시 테스트를 시작할 수 있습니다.

![](./deliver-proxy.png)

### 사용자 정의 헤더 추가

Noir가 전송하는 요청에 사용자 정의 헤더를 추가할 수도 있습니다. 이는 인증 토큰이나 기타 특정 헤더를 포함해야 하는 경우 유용합니다.

```bash
noir -b ./source --send-proxy http://localhost:8080 --with-headers "Authorization: Bearer your-token"
```

![](./deliver-header.png)

### 필터링 및 매칭

발견된 엔드포인트의 일부만 전송하려면 `--use-matchers` 및 `--use-filters` 플래그를 사용할 수 있습니다. 필터링은 여러 패턴을 지원합니다:

#### URL 기반 필터링 (하위 호환성)
URL에 "api"라는 단어가 포함된 엔드포인트만 전송하려면:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "api"
```

#### 메서드 기반 필터링
GET 요청만 전송하려면:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET"
```

모든 POST 요청을 제외하려면:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "POST"
```

#### 메서드와 URL 조합
API 엔드포인트에 대한 POST 요청만 전송하려면:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "POST:/api"
```

관리자 페이지에 대한 GET 요청을 제외하려면:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "GET:/admin"
```

#### 지원되는 HTTP 메서드
메서드 기반 필터링은 모든 표준 HTTP 메서드를 지원합니다: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT (대소문자 구분 안함).

#### 다중 패턴
여러 매처나 필터를 사용할 수 있습니다:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET" --use-matchers "POST:/api"
```

![](./deliver-mf.png)

Deliver 기능을 사용하면 코드 분석과 보안 테스트 간의 원활한 워크플로를 만들어 시간과 노력을 절약할 수 있습니다.