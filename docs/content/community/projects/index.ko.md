+++
title = "연계 작품"
description = "OWASP Noir와 함께 쓰이거나, Noir를 바탕으로 만든 프로젝트."
weight = 10
sort_by = "weight"

+++

Noir를 쓰거나 Noir 옆에 두는 프로젝트입니다. 직접 만든 작품을 올리고 싶다면 이슈나 풀 리퀘스트를 열어 주세요.

## alibi

[alibi](https://github.com/owasp-noir/alibi)는 공격 표면의 관점을 서로 대조하고, 다른 관점이 뒷받침하지 못하는 엔드포인트를 찾습니다. [OWASP Noir](https://github.com/owasp-noir/noir)를 관점마다 한 번씩 실행한 뒤 그 JSON을 비교합니다. Noir는 코드, 계약, 트래픽, 게이트웨이, 인프라를 모읍니다. alibi는 그 결과가 서로 맞는지 확인합니다.

[owasp-noir](https://github.com/owasp-noir) 조직에서 관리하는 공식 도구입니다. `PATH`에 Noir 1.0.0 이상이 필요합니다.

```bash
uv tool install noir-alibi   # 또는: pipx install noir-alibi
alibi scan ./service
```

공개 글: [alibi: 알리바이를 대지 못하는 엔드포인트](@/blog/introducing-alibi/index.ko.md).
