+++
title = "빌드 방법"
description = "개발 환경 설정, 소스 빌드, 테스트 실행 및 OWASP Noir 기여 방법."
weight = 1
sort_by = "weight"

+++

변경 사항을 보내는 방법, Crystal 설치, Noir 빌드, 테스트와 린터 실행을 다룹니다.

{% mascot(mood="good") %}
버그 수정, 기능, 문서, 픽스처. 어떤 기여든 Noir를 앞으로 밀어줘. 와줘서 고마워.
{% end %}

## 기여 방법

1.  [Noir 저장소](https://github.com/owasp-noir/noir)를 **포크**합니다.
2.  **브랜치를 생성**합니다.
    ```sh
    git checkout -b your-feature-name
    ```
3.  **코드를 수정**합니다.
4.  명확한 커밋 메시지와 함께 **커밋**합니다.
5.  포크한 저장소에 **푸시**합니다.
    ```sh
    git push origin your-feature-name
    ```
6.  변경 내용을 적어 **풀 리퀘스트를 엽니다**.

자세한 가이드라인은 [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/.github/CONTRIBUTING.md)를 참조하세요.

## 개발 환경 설정

### Crystal 설치

Noir는 Crystal로 작성되었습니다(`shard.yml` 기준 `~> 1.19`, CI는 1.21과 1.22에서 테스트). 플랫폼에 맞게 설치하세요. 첫 빌드 때 내장된 Tree-sitter 문법도 함께 컴파일하므로 C 컴파일러도 필요합니다.

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt install -y libyaml-dev libzstd-dev zlib1g-dev pkg-config
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### 기타 플랫폼
[Crystal 공식 설치 가이드](https://crystal-lang.org/install/)를 참조하세요.

### 빌드 및 테스트

포크한 저장소를 클론하고 Crystal 패키지 매니저인 `shards`로 의존성을 설치합니다.

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

빌드하면 `./bin/noir`에 바이너리가 생성됩니다.

```sh
shards build
```

프로덕션 빌드는 `--release`를 붙여 만듭니다(컴파일은 느리지만 실행은 2–3배 빠릅니다). 벤치마크를 돌리거나 배포된 릴리스와 비교할 때 쓰세요. 디버그 빌드는 눈에 띄게 느려서 멀쩡한 빌드가 성능 회귀처럼 보일 수 있습니다. `just` 레시피는 공식 릴리스 빌드와 같은 플래그(`--release --no-debug --production`)를 씁니다.

```sh
shards build --release
# 또는 just 레시피 (alias: `just br`)
just build-release
```

테스트를 실행합니다. `just test`는 unit과 functional 스위트를 바이너리 하나(`bin/noir_spec`)로 컴파일한 뒤 두 묶음을 병렬로 돌립니다.

```sh
just test

# 분석기 작업 중에는 functional 테스터 하나만
just test-func-one javascript/hono

# 또는 Crystal 내장 테스트 러너
crystal spec
crystal spec -v
```

### 린팅

Noir는 Crystal 정적 분석 도구인 [Ameba](https://github.com/crystal-ameba/ameba)를 씁니다.

```sh
lib/ameba/bin/ameba.cr
```

문제를 자동으로 고칩니다.

```sh
lib/ameba/bin/ameba.cr --fix
```

또는 `just`를 쓰세요. `just fix`는 포맷과 자동 수정을 하고, `just check`는 CI처럼 검사 결과만 보여줍니다.

```sh
just fix
just check
```
