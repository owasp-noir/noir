+++
title = "빌드 방법"
description = "개발 환경 설정, 소스 빌드, 테스트 실행 및 OWASP Noir 기여 방법."
weight = 1
sort_by = "weight"

+++

버그 수정, 새 기능, 문서 개선 등 모든 기여를 환영합니다.

## 기여 방법

1.  [Noir 저장소](https://github.com/owasp-noir/noir)를 **포크**합니다.
2.  **브랜치를 생성**합니다.
    ```sh
    git checkout -b your-feature-or-fix-name
    ```
3.  **변경 사항을 적용**합니다.
4.  명확한 커밋 메시지와 함께 **커밋**합니다.
5.  포크한 저장소에 **푸시**합니다.
    ```sh
    git push origin your-feature-or-fix-name
    ```
6.  변경 사항 설명을 포함하여 **풀 리퀘스트를 생성**합니다.

자세한 가이드라인은 [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)를 참조하세요.

## 개발 환경 설정

### Crystal 설치

Noir는 Crystal로 작성되었습니다. 플랫폼에 맞게 설치합니다.

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### 기타 플랫폼
[Crystal 공식 설치 가이드](https://crystal-lang.org/install/)를 참조하세요.

### 빌드 및 테스트

포크한 저장소를 클론하고, Crystal의 패키지 매니저인 `shards`로 의존성을 설치합니다.

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

빌드하면 `./bin/noir`에 바이너리가 생성됩니다.

```sh
shards build
```

Crystal 내장 테스트 러너로 테스트를 실행합니다.

```sh
crystal spec

# 더 자세한 출력을 원한다면
crystal spec -v
```

### 린팅

Noir는 Crystal용 정적 분석 도구인 [Ameba](https://github.com/crystal-ameba/ameba)로 코드 스타일을 검사합니다.

```sh
lib/ameba/bin/ameba.cr
```

자동 수정도 가능합니다.

```sh
lib/ameba/bin/ameba.cr --fix
```

또는 `just`를 사용합니다.

```sh
just fix
```
