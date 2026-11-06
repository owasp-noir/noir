+++
title = "엔드포인트 목록 다음에 할 일: query, reach, trace"
description = "Noir 스캔 결과에서 검토 대상을 좁히고, 소스 파일과 연결된 엔드포인트를 찾고, 실제 요청을 라우트에 대응시키는 방법."
date = "2026-11-06"
tags = ["tips", "query", "reach", "trace", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

엔드포인트 목록을 뽑고 나면 다음 질문이 생긴다. 인증 확인이 안 보이는 라우트는 어디일까. 방금 수정한 공통 함수는 어떤 요청에서 사용할까. 프록시에서 본 요청은 어느 핸들러로 들어갈까.

목록을 처음부터 다시 읽는 대신, 알고 있는 정보에서 시작하면 된다. Noir의 `query`는 조건에 맞는 엔드포인트를 고르고, `reach`는 소스 파일에 연결된 엔드포인트를 찾는다. `trace`는 실제 요청에 맞는 라우트를 보여준다.

## 스캔은 한 번, 질문은 여러 번

각 명령에 코드 경로를 넘겨 바로 스캔할 수도 있다. 다만 리뷰하다 보면 질문이 계속 바뀐다. 보고서를 저장해 두면 같은 코드를 매번 스캔하지 않고도 질문을 이어 갈 수 있다.

아래 예시는 [Noir 저장소의 Flask callee fixture](https://github.com/owasp-noir/noir/tree/main/spec/functional_test/fixtures/python/flask_callees)로 Noir 1.5.0에서 직접 실행했다. 저장소 루트에서 시작하며, `noir`가 `PATH`에 있어야 한다. 이 fixture에는 폼을 받는 핸들러와 주문 조회 핸들러, 두 핸들러가 함께 호출하는 함수가 있다. Flask 서버를 띄울 필요는 없다.

```bash
cd spec/functional_test/fixtures/python/flask_callees
noir scan . --ai-context --include callee -f json \
	-o /tmp/noir-review.json --no-log > /dev/null
```

`--ai-context`는 정적 분석으로 리뷰에 필요한 정보를 모은다. AI 제공자를 설정할 필요는 없다. `--include callee`로 호출 정보도 보고서에 남긴다. `scan`은 `-o`로 저장하면서 같은 보고서를 stdout에도 출력하므로, 여기서는 리다이렉션으로 화면 출력을 숨겼다.

직접 스캔할 때와 `--from`으로 읽을 때는 차이가 있다. query 계열 명령이 직접 스캔하면 전체 AI context와 callee 수집이 기본으로 켜진다. 반면 저장된 보고서에는 처음 스캔에서 모은 정보만 있다. 수집하지 않은 guard나 sink가 나중에 생기지는 않는다. 소스 코드를 수정했다면 보고서도 다시 만들어야 한다.

## Query로 먼저 볼 곳을 고른다

`name`이라는 폼 필드를 받는 POST 핸들러 중에서, 인증이나 권한 검사가 기록되지 않은 곳부터 보고 싶다고 하자.

```bash
noir query --method POST --no-guard --param name --param-type form \
	--from /tmp/noir-review.json -f text
```

```text
POST /users  ./app.py:7  python_flask  handler=create_user@./app.py:8  signals=guard_absence
```

이제 `app.py:8`의 `create_user`를 열어 보면 된다. 서로 다른 필터는 AND로 묶이고, 한 필터 안에 쉼표로 나열한 값은 OR다. 따라서 `--method GET,POST`는 둘 중 어느 메서드든 받는다. 파라미터 이름과 타입을 함께 지정하면 같은 파라미터가 두 조건을 모두 만족해야 한다.

`--no-guard`를 곧바로 "인증 없는 엔드포인트"로 읽으면 안 된다. Noir가 인증이나 인가 guard를 기록하지 못했다는 뜻이다. 분석기가 해석하지 못한 미들웨어나 앞단 게이트웨이에서 인증할 수도 있다. rate limit이나 CSRF 검사도 인증 guard에는 포함되지 않는다.

보고서에 데이터베이스 sink가 있다면 `--sink sql`로 대상을 더 좁힐 수 있다. 다만 SQL sink가 있다는 것은 코드를 살펴볼 이유이지, SQL injection이 있다는 판정은 아니다.

## Reach는 바뀐 파일에서 시작한다

이번에는 `helpers.py:5`에 정의된 `run_sql_query`를 수정했다고 하자. 어떤 엔드포인트를 다시 확인해야 할까.

```bash
noir reach helpers.py:5 --from /tmp/noir-review.json -f text
```

```text
POST /users  ./app.py:7  python_flask  handler=create_user@./app.py:8  signals=guard_absence  via=callee:run_sql_query@./helpers.py:5,callee:build_user_query@./helpers.py:1,callee:notify_admin@./helpers.py:10,callee:log_audit@./helpers.py:14
GET /orders/<order_id>  ./app.py:17  python_flask  handler=get_order@./app.py:18  signals=path_param,idor  via=callee:run_sql_query@./helpers.py:5,callee:build_user_query@./helpers.py:1
```

`/users`와 `/orders/<order_id>`가 함께 나온다. `via`에는 `helpers.py`에서 찾은 callee 기록이 들어 있다. 그중 `run_sql_query`의 정의가 지정한 줄에 가장 가까워서 먼저 표시된다.

라인 번호는 일치한 기록의 순서를 정하는 데 쓴다. 그 줄이 들어 있는 함수만 골라 주는 옵션은 아니다. Noir는 선언 위치를 기록하며, 함수의 시작과 끝 전체를 기록하지는 않는다. 줄 번호를 넘기면 JSON과 JSONL 결과에는 `nearest_line`도 포함된다.

파일은 경로의 뒷부분이 일치하는지로 찾으므로 여기서는 `helpers.py`만으로 충분하다. 큰 저장소에 같은 이름의 파일이 여럿 있다면 상위 디렉터리도 포함하는 편이 낫다. 검색 대상은 라우트와 핸들러, callee, guard, source, sink, validator에 기록된 위치다. 모든 호출 관계를 분석하는 기능은 아니며, 상속이나 동적 로딩도 따라가지 않는다. 결과가 없다는 이유만으로 이 파일이 어느 라우트에도 영향을 주지 않는다고 결론 내릴 수는 없다.

## Trace는 실제 요청에서 시작한다

프록시 로그에는 보통 구체적인 경로가 나오고, 코드에는 라우트 템플릿이 있다. 같은 보고서에서 주문 조회 요청을 찾아보자.

```bash
noir trace "GET /orders/42" --from /tmp/noir-review.json -f text
```

```text
GET /orders/<order_id>  ./app.py:17  python_flask  matched_by=pattern  handler=get_order@./app.py:18  signals=path_param,idor
```

`matched_by=pattern`을 보면 `/orders/42`가 `/orders/<order_id>` 패턴에 맞아서 나왔다는 것을 알 수 있다. 저장된 보고서에서 찾는 작업이므로 HTTP 요청은 보내지 않는다.

메서드를 알고 있으면 함께 지정하는 편이 좋다. 생략하면 경로에 맞는 라우트를 메서드 구분 없이 보여준다. HEAD는 GET 라우트에도 대응한다. 일치하는 라우트가 여럿이면 구체적인 결과부터 나온다.

catch-all은 오타가 난 경로도 받아줄 수 있다. 와일드카드나 prefix 라우트만 일치하면 `trace`는 비슷한 후보도 찾아본다. 전혀 일치하지 않을 때는 종료 코드 1을 반환하며, 비슷한 후보를 찾았다면 함께 보여준다. JSON과 JSONL 출력의 `endpoint`에는 일치한 엔드포인트의 전체 기록이 들어가므로, 다시 스캔하지 않고도 파라미터와 context를 확인할 수 있다.

## 다음에 읽을 코드를 찾는 데 쓴다

정해진 순서는 없다. 찾고 싶은 조건이 있으면 `query`, 수정한 파일이 있으면 `reach`, 실제 요청이 있으면 `trace`부터 쓰면 된다. 그다음에는 결과에 나온 근거를 실제 코드와 맞춰 본다.

터미널에서는 text 출력이 읽기 편하다. 스크립트용 기본 출력은 JSONL이고, `query`나 `reach` 결과에 전체 엔드포인트 정보가 필요하면 `--full`을 더한다. `--limit`은 출력할 행 수를 제한한다. `--count`는 개수를 출력하지만, 둘을 같이 쓰면 제한된 행의 개수만 센다. 세 명령 모두 결과가 없으면 종료 코드 1을 반환한다.

스캔 경로나 스캔 전용 플래그는 보고서를 만들 때 지정한다. `--from`은 디렉터리를 스캔하는 대신 보고서를 읽으므로 이 옵션들을 함께 넘기면 사용법 오류가 난다. 전체 필터와 출력 옵션은 [CLI 문서](@/usage/cli_commands/_index.ko.md#trace-reach-query)에서 확인할 수 있다.
