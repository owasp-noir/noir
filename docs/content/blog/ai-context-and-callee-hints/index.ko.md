+++
title = "--ai-context와 --include-callee — AI 코드 리뷰의 hint이자 sink"
description = "AI 기반 소스 코드 분석에서 구조화된 보안 context를 흘려보내는 Noir의 두 플래그 이야기."
date = "2026-05-24"
tags = ["v1", "ai-context", "callee", "design"]
authors = ["hahwul"]
template = "blog_post"
+++

AI의 발전으로 2025년 11월쯤 이후 개발에서 큰 변화가 생겼듯 소스코드 취약점 분석 영역도 해당 시점을 기준으로 빠르게 AI화되고 있습니다.

많은 AI 기반 소스코드 분석 도구나 방법들은 코드를 입력으로 받아서 LLM에 던지고 결과를 받는 패턴을 가지고 있습니다. 그런데 실제로 잘 동작하려면 LLM이 "무엇을 봐야 하는지"를 알려주는 게 중요합니다. 그냥 codebase를 통째로 던지면 token만 태우고, 정작 봐야 할 지점은 놓치는 경우가 많습니다.

Noir v1에는 그 hint를 미리 추출해서 출력에 실어주는 두 플래그가 있습니다.

- `--include-callee`: 각 endpoint 핸들러의 1-hop 호출 그래프를 `callees` 배열로 추가
- `--ai-context`: 같은 callee 정보를 포함해서 **5개 보안 카테고리**로 분류된 `ai_context` 구조로 추가

## --include-callee — who calls whom

가장 단순한 형태입니다. Endpoint 본문을 tree-sitter로 파싱해서 1-hop callee의 `{name, path, line}`을 뽑습니다.

```bash
$ noir -b ./flask_app --include callee -f json
```

```json
{
  "url": "/sign",
  "method": "POST",
  "callees": [
    { "name": "get_hash",          "path": "app/utils.py", "line": 3 },
    { "name": "User.query.filter", "path": "app/app.py",   "line": 21 },
    { "name": "User",              "path": "app/app.py",   "line": 24 },
    { "name": "db_session.add",    "path": "app/app.py",   "line": 25 },
    { "name": "db_session.commit", "path": "app/app.py",   "line": 26 }
  ]
}
```

LLM 입장에서는 "이 endpoint를 보려면 `utils.py:3`과 `app.py:21,24,25,26`을 같이 봐야 한다"는 hint가 됩니다. token 효율도 좋습니다. codebase 전체를 던질 게 아니라 **이 다섯 줄과 그 주변**만 추가로 띄우면 되니까요.

## --ai-context — same data, sorted into security categories

`--ai-context`는 같은 callee 정보를 가져다가 추가 분석을 거쳐 5가지 카테고리로 분류합니다.

- **guards**: 인증 미들웨어 / 데코레이터 등 접근 제어
- **callees**: 위 callee와 동일하지만 snippet과 confidence가 함께 붙음
- **sinks**: SQL / command exec / file I/O / redirect / template render 같은 잠재적 sink
- **validators**: 입력 검증 호출
- **signals**: `state_change`, `credential_input`, `guard_absence` 같은 휴리스틱 신호

같은 Flask `/sign` POST endpoint를 `--ai-context`로 돌리면

```bash
$ noir -b ./flask_app --ai-context -f json
```

```json
{
  "url": "/sign",
  "method": "POST",
  "ai_context": {
    "sinks": [
      {
        "kind": "sql",
        "name": "query",
        "description": "Potential SQL/data-store sink inferred from code or callee name",
        "path": "app/app.py", "line": 21, "confidence": 78,
        "snippet": "20: password = get_hash(request.form['password'], ...) | 21: if User.query.filter(...).first(): | 22: return render_template('error.html')"
      }
    ],
    "signals": [
      { "kind": "state_change",     "name": "POST",          "confidence": 88 },
      { "kind": "credential_input", "name": "form.password", "confidence": 86 },
      { "kind": "guard_absence",    "name": "POST",          "confidence": 28,
        "description": "No auth guard was detected for this state-changing endpoint." }
    ]
  }
}
```

이 endpoint 하나로 LLM이 받는 정보를 정리하면

1. `credential_input`이 있다 (password를 form으로 받음)
2. `state_change`다 (POST)
3. `guard_absence`다 (auth 데코레이터 안 보임)
4. `sql` sink가 있다 (`User.query.filter`)

사람 리뷰어든 LLM이든 이 네 신호가 한 곳에 모여 있다면 자연스럽게 **"이 핸들러 먼저 보세요"**라는 결론이 나옵니다. 회원가입 같은 credential-handling 경로에 auth 부재 = 명백한 priority 1.

반대로 auth가 잡힌 케이스도 봅니다 (flask_auth fixture 출력)

```json
{
  "url": "/profile",
  "method": "GET",
  "ai_context": {
    "guards": [{
      "kind": "auth_guard",
      "name": "flask-login login_required",
      "description": "Protected by flask-login login_required",
      "confidence": 86,
      "snippet": "12: | 13: @login_required | 14: @app.route('/profile') | 15: def profile():"
    }]
  }
}
```

`@login_required` 데코레이터가 잡혀서 `guards`에 채워졌습니다. 이건 LLM에게 "이 endpoint는 auth가 걸려있으니 다른 류의 취약점에 집중하라"는 **negative signal**로도 쓰입니다.

## Hint and sink at the same time

이 두 플래그가 동시에 hint이자 sink로 쓸 수 있다는 게 핵심입니다.

- **Hint**으로: endpoint 단위로 1-hop context를 미리 추려 LLM의 attention을 좁혀줍니다. "전체 코드베이스" 대신 "이 핸들러 + 이 파일들"만 보면 됩니다.
- **Sink**으로: `sinks` 카테고리는 데이터 흐름의 종착점 후보를 framework-aware하게 알려줍니다. 일반 LLM은 "`User.query.filter`는 SQL이다"를 추론은 가능하지만 매번 token을 태워야 합니다. Noir가 미리 라벨링해주면 그 추론 단계를 건너뛸 수 있습니다.

특히 framework-aware라는 점이 큽니다. 같은 `query`라는 callee 이름이라도 컨텍스트에 따라 의미가 다릅니다.

- Flask + SQLAlchemy: `User.query.filter` → SQL sink
- Express + MongoDB: `User.find` → NoSQL sink
- 그냥 generic LLM은 이 차이를 모르거나 매번 reasoning을 다시 합니다

Noir는 detector 단계에서 framework를 식별하고, augmentor가 그 framework의 idiom에 맞춰 sink / guard 패턴을 적용합니다. LLM이 받는 건 raw 코드가 아니라 **이미 framework-aware하게 정리된 context**입니다.

## Recommended use

AI 기반 코드 리뷰 파이프라인을 짠다면

```bash
# 모든 카테고리
noir -b ./app --ai-context -f json

# 필요한 카테고리만 (token 절약)
noir -b ./app --ai-context=guards,sinks,signals -f json

# callee만 (가벼운 hint)
noir -b ./app --include callee -f json
```

전체 카테고리는 첫 audit 때 한 번 돌리는 정도가 적당합니다. 이후 incremental review나 PR 단위에서는 `guards,sinks,signals`만 띄워도 충분한 경우가 많습니다.

## What's next

`--ai-context`의 sink / guard 패턴은 현재 정규식 기반 휴리스틱입니다. 데이터 흐름 자체를 따라가지는 않고, callee 이름과 코드 패턴으로 "여기 sink 같은데" 정도까지만 표시합니다. 이건 의도된 trade-off예요. 정확한 taint analysis는 분리된 도구가 더 잘하고, Noir는 그 도구나 LLM에게 **focus point**를 빠르게 던지는 역할에 충실하려고 합니다.

앞으로는 패턴 카탈로그를 더 framework-aware하게 확장하고, signal 종류를 추가하는 방향으로 진행할 예정입니다. 피드백이나 새 패턴 제안은 언제나 환영합니다.
