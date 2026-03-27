+++
title = "Noir 설치"
description = "Homebrew, Snapcraft, Docker, Nix, 바이너리 다운로드 또는 소스 빌드를 통해 OWASP Noir를 설치합니다."
weight = 2
sort_by = "weight"

+++

{% mascot(mood="think") %}
Noir는 런타임 의존성 없이 단일 바이너리로 배포돼. 대부분의 사용자에게 Homebrew가 가장 빠르지만, 시스템에 맞는 걸 선택해.
{% end %}

## Homebrew (macOS 및 Linux)

가장 간편한 방법. Noir에는 공식 [Homebrew formula](https://formulae.brew.sh/formula/noir)가 있어서 `brew upgrade`로 업데이트까지 한 번에 됩니다.

```bash
brew install noir
```

{% alert_info() %}
Zsh, Bash, Fish용 셸 자동완성이 함께 설치됩니다.
{% end %}

## Snapcraft (Linux)

[Snap](https://snapcraft.io) 패키지는 대부분의 Linux 배포판에서 동작하고, 백그라운드에서 자동 업데이트됩니다.

```bash
sudo snap install noir
```

## Docker

호스트에 직접 설치하고 싶지 않거나, CI/CD 파이프라인에서 쓸 때 유용합니다.

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

현재 디렉토리를 스캔하려면 아래와 같이 실행합니다.

```bash
docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp
```

사용 가능한 태그 목록은 [GitHub Packages 페이지](https://github.com/owasp-noir/noir/pkgs/container/noir)에서 확인할 수 있습니다.

## Nix

[Nix](https://nixos.org) 사용자라면 Flakes로 설치할 수 있습니다.

```bash
nix profile add github:owasp-noir/noir
```

{% alert_info() %}
**팁:** Docker나 제한된 환경에서는 아래처럼 실험적 기능을 활성화해야 할 수 있습니다.
{% end %}

```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```

설치 없이 한 번만 실행해 볼 수도 있습니다.

```bash
nix run github:owasp-noir/noir -- -h
```

## 직접 바이너리 사용

패키지 매니저가 없다면 [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest)에서 빌드된 바이너리를 받을 수 있습니다. Linux와 macOS용이 제공됩니다.

1. 플랫폼에 맞는 압축 파일(예: `noir-linux-x86_64.tar.gz`, `noir-macos-universal.tar.gz`)을 다운로드합니다.
2. 압축을 해제합니다.

    ```bash
    tar xzf noir-*.tar.gz
    ```

3. `PATH`에 있는 디렉터리로 옮깁니다.

    ```bash
    sudo mv noir /usr/local/bin/
    ```

4. 설치를 확인합니다.

    ```bash
    noir --version
    ```

## Debian 패키지 (.deb)

Debian/Ubuntu 계열이라면 [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest)의 `.deb` 패키지를 쓸 수 있습니다. `dpkg`/`apt`로 다른 시스템 패키지처럼 관리됩니다.

1. `.deb` 패키지를 다운로드합니다.

    ```bash
    wget https://github.com/owasp-noir/noir/releases/latest/download/noir_latest_amd64.deb
    ```

2. 패키지를 설치합니다.

    ```bash
    sudo dpkg -i noir_latest_amd64.deb
    ```

3. 의존성이 누락됐다면 아래 명령으로 해결합니다.

    ```bash
    sudo apt-get -f install
    ```

4. 설치를 확인합니다.

    ```bash
    noir --version
    ```

## Unofficial

### Arch AUR

[AUR](https://aur.archlinux.org)에 등록되어 있습니다. 원하는 AUR 헬퍼로 설치하세요.

```bash
yay -S noir
```

## 소스에서 빌드

직접 빌드하거나, 프로젝트에 기여하고 싶을 때 사용합니다.

{% alert_warning() %}
[Crystal](https://crystal-lang.org/install/) 프로그래밍 언어가 필요합니다.
{% end %}

1.  **저장소 클론:**

    ```bash
    git clone https://github.com/owasp-noir/noir
    cd noir
    ```

2.  **종속성 설치:**

    ```bash
    shards install
    ```

3.  **빌드:**

    ```bash
    shards build --release
    ```

    빌드된 바이너리는 `./bin/noir`에 위치합니다.

## 설치 확인

어떤 방법을 선택했든, 아래 명령으로 설치를 확인합니다.

```bash
noir --version
```

버전 번호가 표시되면 준비 완료입니다.

---

**다음**: [첫 번째 스캔](@/get_started/running/index.md)
