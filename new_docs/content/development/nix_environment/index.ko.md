+++
title = "Nix 환경으로 빌드"
description = "Nix와 Docker를 사용하여 OWASP Noir를 위한 재현 가능한 개발 환경을 설정하세요."
weight = 2
sort_by = "weight"

+++

Nix를 사용하여 재현 가능한 개발 환경을 설정할 수 있습니다. 이 접근 방식은 다양한 개발 머신에서 일관성을 보장하고 종속성 관리를 단순화합니다.

## Nix 설치

Nix가 설치되어 있지 않다면 다음 명령으로 설치하세요:

```sh
# 다중 사용자 설치 (Linux/macOS 권장)
sh <(curl -L https://nixos.org/nix/install) --daemon

# 단일 사용자 설치
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

자세한 내용은 [공식 Nix 설치 가이드](https://nixos.org/download.html)를 참조하세요.

## Nix Flakes를 사용한 설정

이 프로젝트는 개발 환경 관리를 위해 Nix Flakes를 사용합니다.

### Flakes 활성화

`~/.config/nix/nix.conf` (또는 `/etc/nix/nix.conf`)에 다음을 추가하세요:

```
experimental-features = nix-command flakes
```

### 개발 셸 진입

```sh
cd noir
nix develop
```

이렇게 하면 Crystal, shards 및 모든 종속성이 자동으로 설정됩니다.

## 대안: Docker와 Nix 사용

완전히 격리된 환경을 원한다면 Docker를 사용할 수 있습니다:

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

컨테이너 내부에서 개발 환경을 활성화합니다:

```sh
nix develop
```

이렇게 하면 Noir 개발에 필요한 모든 종속성과 도구가 격리되고 재현 가능한 환경에 설정됩니다.

## 종속성 업데이트

`shard.yml` 파일을 업데이트할 때 (종속성 추가, 제거 또는 업데이트 시), `shards.nix` 파일도 함께 재생성해야 합니다. 이를 통해 Nix 환경이 프로젝트 종속성과 동기화 상태를 유지할 수 있습니다.

`shard.yml`을 수정한 후 `shards.nix`를 업데이트하려면:

```sh
nix-shell -p crystal2nix --run crystal2nix
```

이 명령은 `crystal2nix` 도구를 사용하여 `shard.yml` 구성을 기반으로 `shards.nix` 파일을 자동으로 생성합니다.

## 장점

- **재현성**: 모든 머신에서 동일한 환경
- **격리**: 시스템 전체 종속성과의 간섭 없음
- **일관성**: 모든 팀원이 동일한 도구 버전을 사용하도록 보장
- **간편한 설정**: 시작하기 위한 단일 명령

## 다음 단계

Nix 환경이 설정되면 표준 [빌드 및 테스트 절차](../how_to_build/)를 진행할 수 있습니다.
