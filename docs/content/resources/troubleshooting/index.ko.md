+++
title = "문제 해결"
description = "OWASP Noir 사용 시 자주 발생하는 문제의 해결 방법입니다."
weight = 2
sort_by = "weight"

+++

{% mascot(mood="anger") %}
뭔가 불이 났어? 아래에서 맞는 증상부터 찾아봐. 대부분 플래그 하나로 해결돼.
{% end %}

## 엔드포인트가 발견되지 않음

**증상:** Noir가 실행되지만 엔드포인트가 0개로 보고됩니다.

- 올바른 디렉터리를 지정했는지 확인하세요: `noir scan ./your-app`
- 프레임워크가 지원되는지 확인하세요: `noir list techs`
- 로그의 탐지 단계를 확인하세요. 감지된 기술이 하나씩 나옵니다. `No technologies detected`가 나오면 `-t`로 프레임워크를 직접 지정하세요: `noir scan . -t rails`
- 지원하지 않는 프레임워크라면 [AI 기반 분석](@/get_started/ai_power/index.ko.md)으로 엔드포인트를 찾으세요

## 스캔이 너무 오래 걸림

**증상:** 대규모 코드베이스에서 Noir가 오래 걸립니다.

- `--only-techs`로 지정한 디텍터만 실행하고 나머지는 건너뛰세요: `noir scan . --only-techs rails`
  (`--techs`는 다릅니다. 탐지 범위를 좁히지 않고 분석 대상에 기술을 추가합니다)
- `--exclude-techs`로 감지됐지만 필요 없는 프레임워크의 분석기를 건너뛰세요(로그에 `(skip)`으로 표시됩니다)
- `--exclude-path`로 vendor·생성 코드 트리를 건너뛰세요: `--exclude-path "vendor/*,**/node_modules/**"`
- AI 기반 분석은 응답을 캐시하므로 같은 코드베이스를 다시 스캔하면 더 빠릅니다

## AI 제공업체 연결 오류

**증상:** `--ai-provider`를 쓰면 오류가 납니다.

- API 키가 올바른지 확인하세요: `--ai-key <KEY>`를 쓰거나 `NOIR_AI_KEY` 환경 변수를 설정하세요
- 로컬 제공업체(Ollama, vLLM, LM Studio)라면 서버가 실행 중인지 확인하세요
- [AI 제공업체](@/usage/ai_providers/_index.ko.md) 비교표에서 기본 호스트를 확인하세요
- 직접 띄운 엔드포인트라면 전체 URL을 쓰세요: `--ai-provider=http://your-server:port`
- ACP 제공업체라면 `NOIR_ACP_RAW_LOG=1`로 디버그 로그를 켜세요

**증상:** AI 분석이 멈춰 있거나, 모델이 아직 생성 중인데 중단됩니다.

- 호스트에 연결할 수 없으면 `NOIR_AI_CONNECT_TIMEOUT`(기본 10초) 후에, 요청은 받았지만 응답이 오지 않으면 `NOIR_AI_TIMEOUT`(기본 300초) 후에 실패합니다
- 느린 로컬 모델이 실제로 더 오래 걸린다면 `NOIR_AI_TIMEOUT`을 늘리고, 대신 번들을 작게 보내려면 `--ai-max-token`을 낮추세요
- 요청 한도 초과(HTTP 429)와 일시적인 게이트웨이 오류(502, 503 등)는 백오프를 두고 재시도하며, 최대 3번까지 시도합니다. 경고가 계속되면 `--concurrency`를 낮추거나 `--ai-max-requests`로 요청 수를 제한하세요
- 모델이 생성하는 동안 유휴 연결을 끊는 프록시나 게이트웨이가 있다면 `--ai-stream`을 추가하세요(OpenAI 호환 제공업체)

## Docker 권한 문제

**증상:** Docker로 실행하면 권한 거부 오류가 납니다.

- 디렉터리가 제대로 마운트되었는지 확인하세요: `docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest noir scan /tmp`
- SELinux 시스템에서는 볼륨 마운트에 `:z`를 추가하세요: `-v $(pwd):/tmp:z`

## 셸 자동완성이 동작하지 않음

**증상:** 설치 후 탭 자동완성이 동작하지 않습니다.

- Homebrew(`brew install noir` 또는 `owasp-noir/noir` tap)로 설치했다면 bash, zsh, fish 자동완성이 자동으로 설정됩니다. 새 셸을 여세요
- 수동 설정은 [셸 자동완성](@/usage/configurations/shell-completion/index.ko.md)을 참조하세요
- 설정 후 셸을 다시 시작하거나 `source ~/.zshrc`(또는 쓰는 셸에 맞는 명령)를 실행하세요

## 추가 도움이 필요하신가요?

- [GitHub 이슈](https://github.com/owasp-noir/noir/issues)를 열어주세요
- [연락처](@/resources/contact/index.ko.md) 페이지에서 팀에 연락하는 다른 방법을 확인하세요
