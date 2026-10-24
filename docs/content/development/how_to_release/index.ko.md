+++
title = "릴리스 방법"
description = "새 Noir 릴리스를 만들고 게시하는 메인테이너 가이드."
weight = 4
sort_by = "weight"

+++

프로젝트 메인테이너용 릴리스 절차입니다.

## 릴리스 채널

| 채널 | 패키지 이름 및 링크 | 릴리스 방식 |
|---|---|---|
| Homebrew (Core) | [noir](https://formulae.brew.sh/formula/noir) | 수동 |
| Homebrew (Tap) | `owasp-noir/noir` | 자동 |
| Snapcraft | [noir](https://snapcraft.io/noir) | 자동 |
| GitHub Container Registry | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | 자동 |
| GitHub 릴리스 첨부 파일 | 바이너리(Linux, macOS, Windows), `.deb`, `.rpm`, `.apk`, SBOM | 자동 |
| AUR | `noir` | 자동 |
| npm | [@owasp-noir/noir](https://www.npmjs.com/package/@owasp-noir/noir) | 자동 |
| OWASP 프로젝트 페이지 | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | 반자동 |

## 일반 절차

1.  **버전 올리기**: 버전이 들어 있는 모든 곳(`shard.yml`, `src/noir.cr`, `flake.nix`, `snap/snapcraft.yaml`, `packaging/` 아래 파일(Dockerfile, `PKGBUILD`, npm `package.json`), GitHub Action README, 일부 문서 파일)을 바꿉니다. 스크립트가 한 번에 처리하며, 인자 없이 실행하면 새 버전을 물어봅니다.

    ```bash
    just version-update 1.4.1
    # 또는
    just vu 1.4.1
    ```

2.  **버전 일관성 확인**: 모든 파일의 버전이 일치하는지 확인합니다.

    ```bash
    just version-check
    # 또는
    just vc
    ```

    추적 대상 파일이 모두 `shard.yml`의 버전과 같아야 하며, 스크립트는 마지막에 `✅ All versions match`를 출력합니다.

3.  **GitHub 릴리스 생성**: [GitHub 릴리스 페이지](https://github.com/owasp-noir/noir/releases)에서 새 릴리스를 게시합니다. 게시하면 자동 워크플로가 돕니다. 바이너리가 먼저 빌드되고, 업로드가 끝나면 `.deb`, `.rpm`, `.apk`, AUR 패키지가 이어집니다. GHCR, Snapcraft, Homebrew tap, SBOM도 함께 처리됩니다. npm은 바이너리 업로드가 끝난 뒤 게시됩니다. 워크플로가 각 바이너리의 SHA-256을 패키지에 고정하고, 패키지는 해시가 맞지 않는 다운로드를 설치하지 않습니다. `package.json` 버전이 릴리스 태그와 다르면 게시를 중단합니다. npm 게시 후에는 해당 릴리스의 바이너리를 다시 빌드하거나 교체하지 마세요. 그 버전의 npm 설치가 체크섬 검사에서 실패하므로, 대신 새 패치 릴리스를 만드세요.
4.  **수동 릴리스**: 나머지 채널은 아래 수동 절차를 따릅니다.

## 수동 릴리스 지침

### Homebrew (Core)

`homebrew-core`에 PR을 올립니다.

1.  **포크 및 동기화**: [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) 포크를 최신 상태로 유지합니다.
2.  **Bump 명령 실행**:

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # 예: brew bump-formula-pr --strict --version 1.4.0 noir
    ```

3.  **스타일 확인** (선택):

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP 프로젝트 페이지

프로젝트 페이지의 버전 목록은 [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir)의 `_data/release.yml`에 있습니다. 정식 릴리스마다 `OWASP Project Page Publish` 워크플로가 새 태그를 `owasp-noir/www-project-noir` 포크에 커밋하고, 실행 요약에 compare 링크를 남깁니다. upstream PR은 그 링크에서 직접 여세요. OWASP Foundation의 토큰 정책 때문에 CI가 PR을 만들 수 없습니다.

예전 태그를 채워 넣거나 실패한 실행을 다시 하려면 같은 스크립트를 로컬에서 실행합니다(`--dry-run`은 푸시하지 않고 변경 내용만 보여줍니다).

```bash
just www-release v1.4.0 --dry-run
just www-release v1.4.0
```
