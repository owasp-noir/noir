+++
title = "숨겨진 플래그로 디버그"
description = "디버깅과 실험을 위한 CLI에 표시되지 않는 개발자용 숨겨진 플래그"
weight = 3
sort_by = "weight"

+++

이 문서는 개발자 전용 숨겨진 플래그를 설명합니다. 해당 플래그들은 `--help` 출력에 나타나지 않지만, 고급 실험과 디버깅 목적으로 사용할 수 있습니다. 이름과 동작은 사전 공지 없이 변경될 수 있습니다.

사용 가능한 플래그

- `--override-analyze-prompt`
  - 개별 파일 분석에 사용되는 내부 ANALYZE_PROMPT를 덮어씁니다.
- `--override-llm-optimize-prompt`
  - 엔드포인트 최적화에 사용되는 내부 LLM_OPTIMIZE_PROMPT를 덮어씁니다.
- `--override-bundle-analyze-prompt`
  - 번들(다중 파일) 분석에 사용되는 내부 BUNDLE_ANALYZE_PROMPT를 덮어씁니다.
- `--override-filter-prompt`
  - 파일 필터링에 사용되는 내부 FILTER_PROMPT를 덮어씁니다.

언제 사용하나요

- 분석/필터링/최적화 단계의 프롬프트 전략을 실험하거나 개선할 때
- 재빌드 없이 프롬프트를 빠르게 변경/반복 테스트하고 싶을 때
- 프롬프트 변화가 결과 품질에 미치는 영향을 비교하고 싶을 때

사용 팁

- 공백과 특수문자를 보존하려면 프롬프트 문자열을 따옴표로 감싸세요.
- 길고 여러 줄인 프롬프트는 파일로 분리하고 명령 치환(`$(cat ...)`)으로 읽어오면 관리가 쉽습니다.
- 먼저 작은 고정 픽스처(예: `spec/functional_test/fixtures/...`)로 동작을 검증한 뒤 범위를 넓히세요.
- 중간 결과를 자세히 보고 싶다면 `--verbose`와 함께 사용하세요.

예시

짧은 리터럴 문자열로 분석 프롬프트 덮어쓰기(개별 파일 분석)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-analyze-prompt 'HTTP 엔드포인트와 파라미터를 식별하고, 간결한 구조화된 결과를 반환하라.'
```

파일에서 여러 줄 프롬프트 읽어오기(분석 프롬프트)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-analyze-prompt "$(cat prompts/analyze_prompt.txt)"
```

LLM 최적화 프롬프트 덮어쓰기

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-llm-optimize-prompt "$(cat prompts/llm_optimize_prompt.txt)"
```

번들(다중 파일) 분석 프롬프트 덮어쓰기

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-bundle-analyze-prompt "$(cat prompts/bundle_analyze_prompt.txt)"
```

파일 필터링 프롬프트 덮어쓰기

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-filter-prompt 'HTTP 라우트나 미들웨어를 선언할 가능성이 있는 애플리케이션 소스만 선택하라.'
```

스크린샷 예시

플래그 없이 실행:

```bash
./bin/noir -b ./spec/functional_test/fixtures/crystal/kemal --ai-provider=lmstudio --ai-model=kanana-nano-2.1b-instruct --exclude-techs kemal --cache-disable
```

![No hidden flag result](images/noflag.jpg)

--override-analyze-prompt 사용:

```bash
./bin/noir -b ./spec/functional_test/fixtures/crystal/kemal --ai-provider=lmstudio --ai-model=kanana-nano-2.1b-instruct --exclude-techs kemal --cache-disable --override-analyze-prompt "This is custom prompt for testttttt"
```

![With hidden flag result](images/withflag.jpg)

주의사항

- 숨겨진 플래그는 개발용이며, 향후 예고 없이 변경되거나 제거될 수 있습니다.
- 프롬프트 내용과 LLM 동작에 따라 출력이 불안정하거나 실행마다 달라질 수 있습니다.
- 셸이 문자를 예기치 않게 해석한다면 리터럴 문자열에는 작은따옴표를, 복잡한 내용은 파일 입력 방식을 권장합니다.
- 최적화 단계 등 LLM 기능을 사용하는 워크플로우라면 관련 환경 설정(API 키 등)을 사전에 준비하세요.
