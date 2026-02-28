+++
title = "Nix 환경으로 빌드"
description = "Nix와 Docker를 사용한 OWASP Noir 재현 가능 개발 환경 설정."
weight = 2
sort_by = "weight"

+++

Nix를 사용하면 머신 간 일관된 종속성을 가진 재현 가능한 개발 환경을 구성할 수 있습니다.

## Nix 설치

```sh
# 다중 사용자 설치 (Linux/macOS 권장)
sh <(curl -L https://nixos.org/nix/install) --daemon

# 단일 사용자 설치
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

자세한 내용은 [공식 Nix 설치 가이드](https://nixos.org/download.html)를 참조하세요.

## Nix Flakes를 사용한 설정

### Flakes 활성화

`~/.config/nix/nix.conf` (또는 `/etc/nix/nix.conf`)에 추가:

```
experimental-features = nix-command flakes
```

### 개발 셸 진입

```sh
cd noir
nix develop
```

Crystal, shards 및 모든 종속성이 자동으로 설정됩니다.

## 대안: Docker와 Nix 사용

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

컨테이너 내부에서:

```sh
nix develop
```

## 종속성 업데이트

`shard.yml` 수정 후 `shards.nix`를 재생성하여 Nix 환경을 동기화합니다:

```sh
nix-shell -p crystal2nix --run crystal2nix
```

## 장점

- **재현성**: 모든 머신에서 동일한 환경
- **격리**: 시스템 전체 종속성과의 간섭 없음
- **일관성**: 모든 팀원이 동일한 도구 버전 사용
- **간편한 설정**: 단일 명령으로 시작

## 다음 단계

[빌드 및 테스트 절차](../how_to_build/)를 진행하세요.
