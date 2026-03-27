+++
title = "Nix 환경으로 빌드"
description = "Nix와 Docker를 사용한 OWASP Noir 재현 가능 개발 환경 설정."
weight = 2
sort_by = "weight"

+++

Nix를 사용하면 머신에 관계없이 동일한 의존성을 가진 재현 가능한 개발 환경을 구성할 수 있습니다.

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

[Flakes](https://nixos.wiki/wiki/Flakes)는 Nix의 재현 가능한 프로젝트 정의 방식입니다. `~/.config/nix/nix.conf`(또는 `/etc/nix/nix.conf`)에 아래 줄을 추가하여 활성화합니다.

```
experimental-features = nix-command flakes
```

### 개발 셸 진입

```sh
cd noir
nix develop
```

Crystal, shards 및 모든 의존성이 자동으로 설정됩니다.

## 대안 - Docker에서 Nix 사용

호스트에 Nix를 설치하고 싶지 않다면, 공식 Nix Docker 이미지로 로컬 레포를 마운트해서 쓸 수 있습니다.

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

컨테이너 안에서 개발 셸에 진입합니다.

```sh
nix develop
```

## 의존성 업데이트

`shard.yml`을 수정한 뒤에는 `shards.nix`를 재생성하여 Nix 환경과 동기화합니다.

```sh
nix-shell -p crystal2nix --run crystal2nix
```

## 장점

- **재현성**: 모든 머신에서 동일한 환경
- **격리**: 시스템 전체 의존성과 충돌 없음
- **일관성**: 모든 팀원이 같은 도구 버전 사용
- **간편한 설정**: 명령 한 줄로 시작

## 다음 단계

[빌드 및 테스트 절차](../how_to_build/)를 진행하세요.
