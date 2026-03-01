+++
title = "릴리스 방법"
description = "Noir 릴리스 생성 및 게시를 위한 관리자 가이드."
weight = 4
sort_by = "weight"

+++

프로젝트 관리자를 위한 릴리스 프로세스입니다.

## 릴리스 채널

| 채널 | 패키지 이름 및 링크 | 릴리스 프로세스 |
|---|---|---|
| Homebrew (Core) | [noir](https://formulae.brew.sh/formula/noir) | 수동 |
| Homebrew (Tap) | `owasp-noir/noir` | 자동화 |
| Snapcraft | [noir](https://snapcraft.io/noir) | 자동화 |
| Docker Hub | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | 자동화 |
| OWASP 프로젝트 페이지 | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | 수동 |

## 일반 절차

1.  **버전 업데이트**: 소스 코드와 문서의 버전을 업데이트합니다.
2.  **버전 일관성 확인**: 모든 파일의 버전 번호가 일치하는지 확인합니다:

    ```bash
    just version-check
    # 또는
    just vc
    ```

    13개 추적 파일이 `shard.yml`의 버전과 일치해야 합니다 (모두 ✅ 표시).

3.  **GitHub 릴리스 생성**: [GitHub 릴리스 페이지](https://github.com/owasp-noir/noir/releases)에서 새 릴리스를 생성합니다. 자동화된 워크플로가 트리거됩니다.
4.  **수동 릴리스**: 자동화되지 않은 채널은 아래 수동 절차를 따릅니다.

## 수동 릴리스 지침

### Homebrew (Core)

`homebrew-core`에 PR을 제출합니다:

1.  **포크 및 동기화**: [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) 포크를 최신 상태로 유지합니다.
2.  **Bump 명령 실행**:

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # 예: brew bump-formula-pr --strict --version 0.28.0 noir
    ```

3.  **스타일 확인** (선택사항):

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP 프로젝트 페이지

[OWASP/www-project-noir](https://github.com/OWASP/www-project-noir)에 업데이트된 내용으로 PR을 제출합니다.
