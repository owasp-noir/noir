+++
title = "문제 해결"
description = "OWASP Noir 사용 시 자주 발생하는 문제의 해결 방법입니다."
weight = 2
sort_by = "weight"

+++

## 엔드포인트가 발견되지 않음

**증상:** Noir가 실행되지만 엔드포인트가 0개로 보고됩니다.

- 올바른 디렉토리를 지정했는지 확인하세요: `noir -b ./your-app`
- 프레임워크가 지원되는지 확인하세요: `noir --list-techs`
- `--verbose`를 사용하여 어떤 기술이 감지되었는지 확인하세요
- 프레임워크가 지원되지 않는 경우 [AI 기반 분석](@/get_started/ai_power/index.md)을 사용하세요

## 스캔이 너무 오래 걸림

**증상:** 대규모 코드베이스에서 Noir가 오래 걸립니다.

- `--techs`로 특정 프레임워크만 스캔하세요: `noir -b . --techs rails`
- `--exclude-techs`로 불필요한 프레임워크를 건너뛰세요
- AI 기반 분석은 응답을 캐시합니다 — 동일한 코드베이스에 대한 후속 실행은 더 빠릅니다

## AI 제공업체 연결 오류

**증상:** `--ai-provider` 사용 시 오류가 발생합니다.

- API 키가 올바른지 확인하세요: `--ai-key <KEY>` 또는 `NOIR_AI_KEY` 환경 변수 설정
- 로컬 제공업체(Ollama, vLLM, LM Studio)의 경우 서버가 실행 중인지 확인하세요
- [AI 제공업체](@/usage/ai_providers/_index.md) 비교표에서 기본 호스트를 확인하세요
- 사용자 정의 엔드포인트의 경우 전체 URL을 사용하세요: `--ai-provider=http://your-server:port`
- ACP 제공업체의 경우 `NOIR_ACP_RAW_LOG=1`로 디버그 로그를 활성화하세요

## Docker 권한 문제

**증상:** Docker로 실행 시 권한 거부 오류가 발생합니다.

- 디렉토리가 올바르게 마운트되었는지 확인하세요: `docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp`
- SELinux 시스템에서는 볼륨 마운트에 `:z`를 추가하세요: `-v $(pwd):/tmp:z`

## 셸 자동완성이 작동하지 않음

**증상:** 설치 후 탭 자동완성이 작동하지 않습니다.

- Homebrew로 설치한 경우 자동완성이 자동으로 설치됩니다
- 수동 설정은 [셸 자동완성](@/usage/configurations/shell-completion/index.md)을 참조하세요
- 설정 후 셸을 재시작하거나 `source ~/.zshrc` (또는 해당 셸의 동등한 명령)를 실행하세요

## 추가 도움이 필요하신가요?

- [GitHub 이슈](https://github.com/owasp-noir/noir/issues)를 열어주세요
- [연락처](@/resources/contact/index.md) 페이지에서 팀에 연락하는 다른 방법을 확인하세요
