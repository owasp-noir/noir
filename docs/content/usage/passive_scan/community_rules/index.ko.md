+++
title = "커뮤니티 기여 패시브 스캔 규칙"
description = "커뮤니티 기여 패시브 스캔 규칙이 배포되는 방식과, 규칙을 기여하거나 별도의 규칙 세트를 사용하는 방법."
weight = 3
sort_by = "weight"

+++

패시브 스캔 규칙은 기본 규칙과 커뮤니티 기여 규칙 모두 하나의 저장소에서 관리됩니다:

*   **[owasp-noir/noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules)**

별도로 설치할 필요는 없습니다. 패시브 스캔을 활성화(`-P`)하면 Noir가 첫 실행 시 이 저장소를 `~/.config/noir/passive_rules/`로 클론하고, 규칙이 뒤처지면 알려줍니다. `--passive-scan-auto-update`를 추가하면 시작 시 최신 규칙을 자동으로 받아오며, 해당 디렉터리에서 직접 `git pull`을 실행해도 됩니다.

## 규칙 기여하기

커뮤니티에 규칙을 공유하려면 [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) 저장소에 Pull Request를 보내세요. 머지되면 모든 Noir 사용자가 일반적인 규칙 업데이트 흐름을 통해 해당 규칙을 받게 됩니다. 규칙 형식은 [패시브 스캔 규칙](../rule/) 문서를 참고하세요.

## 서드파티/커스텀 규칙 세트 사용하기

다른 곳(사설 저장소, 로컬 디렉터리)의 규칙 세트를 사용하려면 `--passive-scan-path`로 지정하세요:

```bash
noir scan /app -P --passive-scan-path ./my-rules/
```

이 플래그를 사용하면 해당 실행에서는 기본 규칙 대신 지정한 규칙이 사용되며, 여러 번 지정해 여러 디렉터리나 파일을 함께 로드할 수 있습니다. 또는 `~/.config/noir/passive_rules/`에 `.yml`/`.yaml` 파일을 추가해도 됩니다. 이 디렉터리는 하위 경로까지 재귀적으로 로드됩니다.
