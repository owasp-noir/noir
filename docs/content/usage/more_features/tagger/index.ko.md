+++
title = "상황별 분석을 위한 Tagger 사용하기"
description = "엔드포인트와 매개변수에 자동으로 태그를 추가하여 잠재적 보안 위험을 식별합니다."
weight = 3
sort_by = "weight"

+++

엔드포인트와 파라미터에 설명적 태그를 자동으로 추가하여 기능과 잠재적 보안 위험(SQL 인젝션, 인증 엔드포인트 등)을 식별합니다.

![](./tagger.png)

## 사용법

Tagger는 기본적으로 비활성화되어 있습니다.

**모든 태거 활성화**

```bash
noir scan <BASE_PATH> -T
```

**특정 태거만 활성화** (`noir list taggers`로 목록 확인)

```bash
noir scan <BASE_PATH> --use-taggers hunt,oauth
```

## 출력

태그는 엔드포인트 레벨과 파라미터 레벨 양쪽의 `tags` 배열에 추가됩니다. 각 태그에는 `name`(짧은 식별자, 예: `sqli`, `oauth`), 사람이 읽을 수 있는 `description`, 그리고 태그를 생성한 `tagger`(예: `Hunt`는 취약점 패턴, `Oauth`는 인증 흐름)가 들어갑니다.

```json
{
  "url": "/query",
  "method": "POST",
  "params": [
    {
      "name": "query",
      "value": "",
      "param_type": "form",
      "tags": [
        {
          "name": "sqli",
          "description": "This parameter may be vulnerable to SQL Injection attacks.",
          "tagger": "Hunt"
        }
      ]
    }
  ],
  "protocol": "http",
  "tags": []
},
{
  "url": "/token",
  "method": "GET",
  "protocol": "http",
  "tags": [
    {
      "name": "oauth",
      "description": "Suspected OAuth endpoint for granting 3rd party access.",
      "tagger": "Oauth"
    }
  ]
}
```

## 태그 분류

태거는 여러 종류의 보안 관련 신호를 다룹니다. 전체 최신 목록은 `noir list taggers`로 확인하세요.

- **파라미터 취약점 클래스** — `hunt`는 알려진 위험 이름과 일치하는 개별 파라미터를 표시합니다(`sqli`, `ssrf`, `idor`, `file-inclusion`, `command-injection` 등).
- **프로토콜 / 인터페이스** — `graphql`, `soap`, `websocket`, `mcp`, `cors`.
- **인증 & 토큰** — `oauth`, `jwt`, 그리고 프레임워크 인지 인증 태거(Spring Security, Django, Express 등).
- **엔드포인트 민감도 & 용도** — 엔드포인트가 *무엇을 위한 것인지* 분류하여, 리뷰어가 가장 중요한 표면에 우선순위를 둘 수 있게 합니다:
  - `pii` — 개인식별정보(주민번호, 카드 정보, 연락처)를 다루는 엔드포인트. 데이터 노출 및 과도한 수집 검토 대상.
  - `admin` — 관리/특권 라우트(`/admin`, 권한 변경 파라미터). 깨진 접근 제어 및 권한 상승의 주요 표적.
  - `payment` — 결제/금융 트랜잭션 엔드포인트. 금액·가격 조작, 통화 혼동, 금융 레코드 IDOR 검토 대상.
  - `webhook` — 인바운드 웹훅/콜백 엔드포인트. 서명 검증, 재전송 방어, 아웃바운드 호출의 SSRF 검토 대상.
  - `file_upload` — 파일 업로드 엔드포인트. 무제한 업로드, 경로 탐색, 악성 파일 처리 검토 대상.

엔드포인트 레벨 태그는 AI 컨텍스트에도 신호로 전달되어, AI 리뷰어가 사용하는 엔드포인트별 요약을 더욱 풍부하게 만듭니다.
