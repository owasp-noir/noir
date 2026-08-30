+++
title = "Nix 환경으로 빌드"
description = "Nix와 Docker를 사용한 OWASP Noir 재현 가능 개발 환경 설정."
weight = 2
sort_by = "weight"

+++

Nix를 사용하면 머신에 관계없이 동일한 의존성을 가진 재현 가능한 개발 환경을 구성할 수 있습니다. 시스템 전역 패키지와도 분리됩니다.

## Nix 설치

다중 사용자(daemon) 설치가 동시 빌드와 격리 면에서 유리합니다. 단일 사용자 설치는 더 간단하지만 백그라운드 데몬 없이 동작합니다.

```sh
# 다중 사용자 설치 (Linux/macOS 권장)
sh <(curl -L https://nixos.org/nix/install) --daemon

# 단일 사용자 설치
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

자세한 내용은 [공식 Nix 설치 가이드](https://nixos.org/download.html)를 참조하세요.

## Nix Flakes를 사용한 설정

### Flakes 활성화

[Flakes](https://wiki.nixos.org/wiki/Flakes)는 Nix의 재현 가능한 프로젝트 정의 방식입니다. `~/.config/nix/nix.conf`(또는 `/etc/nix/nix.conf`)에 아래 줄을 추가하여 활성화합니다.

```
experimental-features = nix-command flakes
```

### 개발 셸 진입

```sh
cd noir
nix develop
```

셸에는 Crystal, shards, `just`와 Noir가 링크하는 네이티브 라이브러리가 함께 들어옵니다. 샤드 의존성 자체는 여전히 `./lib`에 설치되므로, 셸 안에서 한 번 설치한 뒤 평소처럼 빌드하면 됩니다.

```sh
shards install
just build
```

## 대안 - Docker에서 Nix 사용

호스트에 Nix를 설치하고 싶지 않다면, 공식 Nix Docker 이미지로 로컬 레포를 마운트해서 쓸 수 있습니다.

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

컨테이너 안에서 개발 셸에 진입합니다.

```sh
nix develop
```

## 패키지 빌드

플레이크는 릴리스 바이너리도 빌드합니다. 사용자가 `nix profile add github:owasp-noir/noir`로 설치할 때와 동일한 경로이며, 다른 공식 빌드와 같은 플래그(`--release --no-debug`)를 사용합니다.

```sh
just nix-build
./result/bin/noir -h
```

## 의존성 업데이트

`shards.nix`는 Nix 빌드가 사용하는 모든 의존성을 리비전과 해시로 고정하며, 손으로 작성하지 않고 생성합니다. `shard.lock`이 바뀌면 재생성한 뒤 둘이 일치하는지 확인하세요.

```sh
just nix-update
just nix-check
```

CI에서도 같은 검사를 수행하므로, 재생성을 빠뜨렸다면 릴리스 후 첫 Nix 설치가 아니라 리뷰 단계에서 드러납니다.

고정된 nixpkgs를(그리고 패키지가 빌드에 사용하는 Crystal 툴체인을) 최신으로 옮기려면 다음을 실행합니다.

```sh
nix flake update
```

## 다음 단계

[빌드 및 테스트 절차](../how_to_build/)를 진행하세요.
