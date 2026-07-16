+++
title = "개발"
description = "OWASP Noir에 기여하는 개발자를 위한 리소스: 빌드, 개발 환경 설정, 디버깅 도구, 릴리스 절차."
weight = 10
sort_by = "weight"


[cascade]
toc = true

+++

Noir에 기여할 때 필요한 가이드를 모았습니다. 소스 빌드, 분석기 아키텍처, 디버그 플래그, 릴리스 절차를 다룹니다.

*   **[빌드 방법](how_to_build/)**: 개발 환경 설정, 프로젝트 빌드, 테스트 실행.
*   **[분석기 아키텍처](analyzer_architecture/)**: 3-layer 구조(engine → route extractor → framework adapter) 와 새 detector/analyzer 를 추가하는 단계별 가이드.
*   **[Nix 환경으로 빌드](nix_environment/)**: Nix와 Docker로 만드는 재현 가능한 개발 환경.
*   **[숨겨진 플래그로 디버그](debug_flags/)**: 디버깅과 실험을 위한 개발자 전용 플래그.
*   **[릴리스 방법](how_to_release/)**: 새 릴리스를 만들고 게시하는 관리자용 가이드.
