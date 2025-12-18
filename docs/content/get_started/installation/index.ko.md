+++
title = "설치"
description = "시스템에 OWASP Noir를 설치하는 방법을 알아보세요. 이 가이드는 Homebrew, Snapcraft, Docker, Nix를 사용하거나 소스에서 빌드하여 Noir를 설치하는 지침을 제공합니다."
weight = 2
sort_by = "weight"

[extra]
+++

OWASP Noir를 설치하는 방법은 여러 가지가 있으므로 운영 체제와 워크플로에 가장 적합한 방법을 선택할 수 있습니다.

## Homebrew (macOS 및 Linux)

macOS 또는 Linux를 사용하는 경우 Noir를 설치하는 가장 쉬운 방법은 [Homebrew](https://brew.sh/)를 사용하는 것입니다.

```bash
brew install noir
```

{% alert_info() %}
Homebrew 사용자의 경우 Zsh, Bash, Fish용 셸 완성 기능이 자동으로 설치되므로 바로 사용할 수 있습니다.
{% end %}

## Snapcraft (Linux)

[Snap](https://snapcraft.io/)을 지원하는 Linux 배포판을 사용하는 경우 Snap Store에서 Noir를 설치할 수 있습니다.

```bash
sudo snap install noir
```

## Docker

시스템에 Noir를 설치하지 않고 사용하려면 Docker를 사용할 수 있습니다.

```bash
docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp
```

이 명령은 현재 디렉토리를 Docker 컨테이너에 마운트하고 Noir를 실행하여 코드를 분석합니다.

## Nix

[Nix](https://nixos.org/)를 사용하여 설치합니다:

```bash
nix profile add --no-write-lock-file github:owasp-noir/noir
```

{% alert_info() %}
**팁:** Docker 또는 제한된 환경에서는 실험적 기능을 활성화해야 할 수 있습니다:
```bash
nix --extra-experimental-features "nix-command flakes" profile add --no-write-lock-file github:owasp-noir/noir
```
{% end %}

또는 직접 실행할 수 있습니다:

```bash
nix run github:owasp-noir/noir -- -h
```

## 직접 바이너리 사용

GitHub Releases에서 Noir 바이너리를 직접 다운로드하여 사용할 수 있습니다.

1. GitHub Releases 페이지에 접속합니다:

   https://github.com/owasp-noir/noir/releases/latest

2. 사용하는 운영체제와 아키텍처에 맞는 압축 파일(예: `noir-x86_64-unknown-linux-gnu.tar.gz`, `noir-x86_64-apple-darwin.tar.gz` 등)을 다운로드합니다.
3. 압축을 해제합니다:

   ```bash
   tar -xzf noir-*.tar.gz
   ```

4. 실행 파일에 실행 권한을 부여합니다:

   ```bash
   chmod +x noir
   ```

5. PATH에 있는 디렉터리로 옮기면 어디서나 실행할 수 있습니다:

   ```bash
   sudo mv noir /usr/local/bin/
   ```

이제 다음과 같이 실행하여 버전을 확인할 수 있습니다:

```bash
noir --version
```

## Debian 패키지(.deb)

Debian 또는 Ubuntu 계열 배포판을 사용하는 경우 `.deb` 패키지를 설치할 수 있습니다.

1. GitHub Releases 페이지에서 최신 `.deb` 패키지를 다운로드합니다:

   https://github.com/owasp-noir/noir/releases/latest

   예: `noir_latest_amd64.deb` 와 같은 파일

2. `dpkg`로 패키지를 설치합니다:

   ```bash
   sudo dpkg -i noir_*_amd64.deb
   ```

3. 필요한 경우 누락된 의존성을 자동으로 설치합니다:

   ```bash
   sudo apt-get install -f
   ```

설치가 완료되면 다음 명령으로 설치 여부를 확인할 수 있습니다:

```bash
noir --version
```

## Unofficial

### Arch AUR

Arch Linux를 사용하는 경우 [AUR](https://aur.archlinux.org/packages/noir)에서 Noir를 설치할 수 있습니다.

```bash
yay -S noir
```

또는 다른 AUR 헬퍼를 사용할 수 있습니다.

## 소스에서 빌드

더 많은 제어가 필요하거나 개발에 기여하고 싶다면 소스에서 Noir를 빌드할 수 있습니다.

### 필수 조건

Noir를 빌드하려면 다음이 필요합니다:

*   [Crystal](https://crystal-lang.org/install/) (v1.10 이상)
*   [Shards](https://crystal-lang.org/reference/man/shards/) (Crystal 패키지 관리자)

### 빌드 단계

1.  저장소를 클론합니다:

    ```bash
    git clone https://github.com/owasp-noir/noir.git
    cd noir
    ```

2.  종속성을 설치합니다:

    ```bash
    shards install
    ```

3.  애플리케이션을 빌드합니다:

    ```bash
    shards build --release
    ```

4.  바이너리는 `./bin/noir`에 위치합니다.

### 설치 확인

설치가 성공했는지 확인하려면 버전을 확인하세요:

```bash
noir --version
```

이 명령은 설치된 Noir의 버전을 출력해야 합니다.