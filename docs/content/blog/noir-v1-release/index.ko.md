+++
title = "Noir v1.0 — 메이저 버전, v0은 그대로"
description = "왜 1.x로 갔는지, 그리고 호환을 어떻게 지켰는지."
date = "2026-05-23"
tags = ["release", "v1"]
authors = ["hahwul"]
template = "blog_post"
+++

Noir v1.0이 나왔습니다.

메이저 버전을 올린 이유는 두 가지입니다.

**하나, 안정성.** v0.30 즈음부터 새 framework가 들어와도 기존 분석 결과가 깨지지 않는 단계에 도달했다고 판단했습니다. 분석기 contract, 출력 스키마, 디스크 경로 — 핵심 인터페이스들이 자리를 잡았고, 이제는 1.x라고 부를만한 시점이라 생각했습니다.

**둘, sub-commands.** v0의 CLI는 flag-only였습니다. 캐시, 룰, 설정 같은 부가 기능이 더 늘어날 게 보이는 상황에서 flag만으로는 표현이 한계에 부딪혔습니다. v1에서는 `noir scan / list / cache / config / rules / completion / version / help` 형태로 verb 기반 구조를 도입했습니다.

이 두 결정 외에는 거의 모든 변화를 **v0 호환 위주로 설계**했습니다. `noir -b ./app -P -f json` 같은 v0 호출은 router가 자동으로 `scan`으로 라우팅하고, 정리된 옛 flag 이름들은 silent alias로 살아있습니다. 명시적으로 깨지는 건 2024년부터 deprecation 안내가 떠 있던 `--ollama` / `--ollama-model` 둘뿐입니다.

대부분의 v0 스크립트는 코드 한 줄 안 고쳐도 v1에서 그대로 돌아갑니다. 그게 이번 릴리스의 핵심 메시지입니다.

전체 변경 목록과 마이그레이션이 필요한 항목은 [CHANGELOG v1.0.0](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100)에 정리해두었습니다.

업그레이드는 익숙한 경로 그대로 가능합니다.

```bash
brew upgrade noir
# 또는
docker pull ghcr.io/owasp-noir/noir:1.0.0
# 또는
gh release download v1.0.0 -R owasp-noir/noir
```

피드백이나 회귀 발견 시 [GitHub Issues](https://github.com/owasp-noir/noir/issues)로 알려주세요. 그럼 즐거운 hunting 되시길 바라며 마치겠습니다.
