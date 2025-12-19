+++
title = "릴리스 방법"
description = "Noir의 새로운 릴리스를 생성하고 게시하는 방법에 대한 관리자 가이드입니다. 이 페이지는 Homebrew, Snapcraft, Docker Hub와 같은 플랫폼에 릴리스하는 수동 및 자동화된 단계를 설명합니다."
weight = 4
sort_by = "weight"

[extra]
+++

이 문서는 Noir의 새로운 릴리스를 생성하고 게시하는 프로세스를 설명합니다. 프로젝트 관리자를 위한 문서입니다.

## 릴리스 채널

Noir는 여러 채널을 통해 배포됩니다. 일부는 GitHub Actions를 통해 자동으로 업데이트되며, 다른 것들은 수동 개입이 필요합니다.

| 채널 | 패키지 이름 및 링크 | 릴리스 프로세스 |
|---|---|---|
| Homebrew (Core) | [noir](https://formulae.brew.sh/formula/noir) | 수동 |
| Homebrew (Tap) | `owasp-noir/noir` | 자동화 |
| Snapcraft | [noir](https://snapcraft.io/noir) | 자동화 |
| Docker Hub | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | 자동화 |
| OWASP 프로젝트 페이지 | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | 수동 |

## 일반 절차

1.  **버전 업데이트**: Noir 소스 코드와 관련 문서의 패키지 버전이 업데이트되었는지 확인합니다.
2.  **버전 일관성 확인**: 릴리스를 생성하기 전에 버전 일관성 검사를 실행하여 모든 파일의 버전 번호가 일치하는지 확인합니다:

    ```bash
    just version-check
    # 또는
    just vc
    ```

    이 명령은 추적되는 13개 파일의 버전 문자열이 모두 `shard.yml`의 버전과 일치하는지 확인합니다. 릴리스를 진행하기 전에 모든 검사가 통과(✅ 표시)해야 합니다.

3.  **GitHub 릴리스 생성**: [GitHub 릴리스 페이지](https://github.com/owasp-noir/noir/releases)에서 새 릴리스를 생성합니다. 이는 자동화된 릴리스 워크플로를 트리거합니다.
4.  **수동 릴리스**: 자동화되지 않은 채널에 대해서는 수동 릴리스 절차를 따릅니다.

## 수동 릴리스 지침

### Homebrew (Core)

메인 Homebrew 공식을 업데이트하려면 `homebrew-core` 저장소에 풀 리퀘스트를 제출해야 합니다.

1.  **포크 및 동기화**: [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) 저장소의 포크가 있고 최신 상태인지 확인합니다.
2.  **Bump 명령 실행**: `brew bump-formula-pr` 명령을 사용하여 새 버전으로 풀 리퀘스트를 자동으로 생성합니다.

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # 예: brew bump-formula-pr --strict --version 0.26.0 noir
    ```

3.  **스타일 확인**: (선택사항) 변경 사항이 Homebrew의 스타일 가이드라인을 충족하는지 확인하려면 다음을 실행할 수 있습니다:

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP 프로젝트 페이지

OWASP 프로젝트 페이지를 업데이트하려면 [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) 저장소에 풀 리퀘스트를 제출해야 합니다.

이 프로세스는 일반적으로 새로운 주요 기능이나 중요한 마일스톤이 있을 때만 필요합니다.
