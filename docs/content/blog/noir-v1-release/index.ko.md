+++
title = "Noir v1.0 출시 — 메이저 버전, 그래도 v0은 그대로"
description = "왜 지금 1.x로 갔는지, 어떤 결정이 깨졌고 어떤 건 그대로 두었는지, 그리고 RC에서 잡은 production 버그 한 토막."
date = "2026-05-23"
tags = ["release", "v1"]
authors = ["hahwul"]
template = "blog_post"
+++

Noir v1.0이 나왔습니다.

v0 → v1으로 메이저 버전을 올린 데에는 두 가지 이유가 있습니다.

**첫 번째는 안정성입니다.** Noir는 첫 커밋 이후 분석기, 태거, 패시브 스캔의 surface를 빠르게 넓혀왔는데, v0.30 즈음부터는 새 framework가 들어와도 기존 분석 결과가 깨지지 않는 단계에 도달했다고 판단했습니다. 분석기 contract, 출력 스키마, 디스크 경로 — 핵심 인터페이스들이 충분히 안정적이게 자리를 잡았습니다. 이제는 1.x라고 부를만한 시점입니다.

**두 번째는 sub-commands 도입입니다.** v0의 CLI는 flag-only였습니다. 모든 동작이 `noir [flags]` 하나로 묶여있었죠. 캐시 관리, 룰 관리, 설정 관리 같은 부가 기능이 더 늘어날 게 보이는 상황에서 flag만으로는 표현이 한계에 부딪힌다고 느꼈습니다. v1에서는 `noir scan / list / cache / config / rules / completion / version / help` 형태로 verb 기반 구조를 도입했습니다.

이 두 결정 외에는 **거의 모든 변화를 v0 호환 위주로 설계**했습니다.

## v0 스크립트는 그대로 동작합니다

`noir -b ./app -P -f json -o out.json` 같은 v0 호출 형태는 무수정 그대로 v1에서 돌아갑니다. router가 leading flag를 보면 자동으로 `scan` 서브커맨드로 라우팅합니다. CI 파이프라인, GitHub Action, Dockerfile entrypoint, shell alias — 어디에 박혀 있든 영향받지 않습니다.

flag 이름이 정리된 경우에도 옛 이름이 silent alias로 살아있습니다.

- `--set-pvalue VAL` (+ header/cookie/query/form/json/path 변형 6개) → 새 `--pvalue TYPE=VAL`의 별칭
- `--include-path` / `--include-techs` / `--include-callee` → 새 `--include LIST`의 별칭
- `--list-techs`, `--list-taggers`, `--build-info`, `--help-all`, `-v` / `--version`, `--generate-completion SHELL` → 각각 해당 subcommand로 자동 rewrite

명시적으로 깨지는 건 `--ollama URL` / `--ollama-model NAME` 두 개뿐입니다. 이건 2024년부터 deprecation 안내가 떠 있던 것들이고, v1에서는 호출 자체가 거부되며 한 줄짜리 마이그레이션 힌트(`--ai-provider ollama [--ai-model NAME]`)가 출력됩니다.

## RC에서 잡힌 production 버그 한 토막

v1 RC를 돌면서 흥미로운 버그를 하나 잡았습니다. `--send-es URL` (Elasticsearch 전송) 이 모든 호출에서 빈 POST body를 보내고 있었습니다.

원인은 Crystal HTTP 클라이언트 Crest의 시그니처였습니다. `Crest::Request.execute(method: :post, body: ..., json: true)` 호출에서 `body:`라는 키워드를 명시적으로 처리하지 않고 `**options`에 흡수해버립니다. 이 라이브러리에서 body의 정식 슬롯은 `form:`이고, `json: true`와 함께 쓰면 string으로 들어온 payload를 그대로 JSON으로 송신합니다.

코드는 `body: body`로 적혀 있었고, 컴파일도 통과했고, HTTP 요청도 200을 받아왔고, 로그도 멀쩡했습니다. 단지 Elasticsearch 서버가 받는 body가 비어 있을 뿐이었습니다. delivery layer에 spec이 없어서 한 릴리스 사이클 동안 깔려 있던 거죠. `body:` → `form:` 한 글자 바꾸고, 회귀 spec으로 in-process HTTP 서버를 띄워 실제 body 도착 여부를 검증하도록 잠갔습니다.

비슷한 패턴으로 Deliver / OutputBuilder / Tagger / PassiveScan / ConfigInitializer 각 layer에서 latent 버그들을 함께 정리했습니다. spec 없이 굴러가던 코드 길에 spec을 깔면서 잡힌 것들이라, 정리 작업의 부수 효과로 production 결함이 줄어든 셈입니다. 전체 목록은 [CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100)에 있습니다.

## Docker / GitHub Action도 깔끔하게

이전엔 GitHub Action용 `github-action/Dockerfile`이 따로 있어서 매 워크플로우 호출마다 `FROM ghcr.io/owasp-noir/noir:1.0.0` + jq apt-install로 이미지를 다시 빌드했습니다. 메이저 릴리스마다 그 `1.0.0` 부분을 수동으로 bump해야 했고, jq 설치 비용도 매번 들었습니다.

v1에서는:

- 메인 `Dockerfile` 하나로 통합 (jq, entrypoint.sh, GH Actions 라벨 포함)
- `action.yml`을 `using: composite`로 바꿔서 미리 빌드된 ghcr 이미지를 `docker pull` + `docker run`
- 이미지 tag는 `github.action_ref`로 자동 매핑 (`@v1.0.0` → `ghcr.io/owasp-noir/noir:1.0.0`)
- 이미지에 `noir-passive-rules` snapshot을 burn해서 컨테이너 안에서도 `-P`가 git 없이 즉시 동작

GitHub Action의 `with:` 입력과 outputs는 v0과 동일합니다. 사용자 입장에선 첫 호출이 빨라진 정도만 체감됩니다.

## 출력 JSON도 호환

Endpoint JSON에 두 필드를 추가했습니다: `callees` (1-hop call graph)와 `ai_context` (`--ai-context` 켰을 때만 채워짐). 기존 필드는 이름과 의미가 그대로 유지됩니다. unknown key를 허용하는 JSON consumer는 (대부분 그렇습니다) 코드 수정 없이 그대로 받습니다.

SARIF strict mode처럼 schema validator가 엄격한 경우에만 새 키 두 개를 allow-list에 추가하면 됩니다.

## 다음

v1.0은 시작점입니다. 1.x 라인 동안엔 callee / AI-context 같은 enrichment surface 확장, passive scan 룰 카테고리의 명시적 노출, secret-detection 외의 SAST-lite 영역 정도가 다음 단계로 잡혀 있습니다. 여전히 v0 호환을 깨지 않으면서요.

전체 변경 목록은 [CHANGELOG v1.0.0](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100)에 있습니다.

업그레이드는 익숙한 경로 그대로 가능합니다.

```bash
brew upgrade noir
# 또는
docker pull ghcr.io/owasp-noir/noir:1.0.0
# 또는
gh release download v1.0.0 -R owasp-noir/noir
```

피드백이나 회귀 발견 시 [GitHub Issues](https://github.com/owasp-noir/noir/issues)로 알려주세요. 그럼 즐거운 hunting 되시길 바라며 마치겠습니다.
