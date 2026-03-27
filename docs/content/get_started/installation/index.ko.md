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

```bash
brew install noir
```

{% alert_info() %}
Zsh, Bash, Fish용 셸 완성 기능이 자동으로 설치됩니다.
{% end %}

## Snapcraft (Linux)

```bash
sudo snap install noir
```

## Docker

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

현재 디렉토리에서 스캔 실행:

```bash
docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp
```

사용 가능한 모든 태그는 [GitHub Packages 페이지](https://github.com/owasp-noir/noir/pkgs/container/noir)에서 확인할 수 있습니다.

## Nix

```bash
nix profile add github:owasp-noir/noir
```

{% alert_info() %}
**팁:** Docker 또는 제한된 환경에서는 실험적 기능을 활성화해야 할 수 있습니다. 아래 명령어를 사용하세요.
{% end %}

```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```

설치 없이 직접 실행:

```bash
nix run github:owasp-noir/noir -- -h
```

## 직접 바이너리 사용

[GitHub Releases](https://github.com/owasp-noir/noir/releases/latest)에서 바이너리를 다운로드합니다.

1. 플랫폼에 맞는 압축 파일(예: `noir-x86_64-unknown-linux-gnu.tar.gz`)을 다운로드합니다.
2. 압축 해제:

   ```bash
   tar -xzf noir-*.tar.gz
   ```

3. 실행 권한 부여:

   ```bash
   chmod +x noir
   ```

4. `PATH`에 있는 디렉터리로 이동:

   ```bash
   sudo mv noir /usr/local/bin/
   ```

5. 확인:

   ```bash
   noir --version
   ```

## Debian 패키지(.deb)

[GitHub Releases](https://github.com/owasp-noir/noir/releases/latest)에서 `.deb` 패키지를 사용합니다.

1. `.deb` 패키지 다운로드:

   ```bash
   wget https://github.com/owasp-noir/noir/releases/latest/download/noir_latest_amd64.deb
   ```

2. 설치:

   ```bash
   sudo dpkg -i noir_*_amd64.deb
   ```

3. 누락된 의존성 설치 (필요한 경우):

   ```bash
   sudo apt-get install -f
   ```

4. 확인:

   ```bash
   noir --version
   ```

## Unofficial

### Arch AUR

```bash
yay -S noir
```

## 소스에서 빌드

{% alert_warning() %}
Crystal 프로그래밍 언어가 설치되어 있어야 합니다.
{% end %}

1.  **저장소 클론:**

    ```bash
    git clone https://github.com/owasp-noir/noir.git
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

어떤 방법을 선택했든, Noir가 설치되었는지 확인하세요:

```bash
noir --version
```

버전 번호가 표시되면 준비 완료입니다.

---

**다음**: [첫 번째 스캔](@/get_started/running/index.md)
