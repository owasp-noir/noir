+++
title = "설치"
description = "시스템에 OWASP Noir를 설치하는 방법을 알아보세요. 이 가이드는 Homebrew, Snapcraft, Docker를 사용하거나 소스에서 빌드하여 Noir를 설치하는 지침을 제공합니다."
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