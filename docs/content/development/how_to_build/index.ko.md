+++
title = "빌드 방법"
description = "개발 환경 설정, 소스 빌드, 테스트 실행 및 OWASP Noir 기여 방법."
weight = 1
sort_by = "weight"

+++

버그 수정, 새 기능, 문서 개선 등 모든 기여를 환영합니다.

## 기여 방법

1.  **포크**: [Noir 저장소](https://github.com/owasp-noir/noir)를 포크합니다.
2.  **브랜치 생성**:
    ```sh
    git checkout -b your-feature-or-fix-name
    ```
3.  **변경 사항 적용**
4.  **커밋**: 명확한 커밋 메시지 작성
5.  **푸시**:
    ```sh
    git push origin your-feature-or-fix-name
    ```
6.  **풀 리퀘스트 생성**: 변경 사항에 대한 설명 포함

자세한 가이드라인은 [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)를 참조하세요.

## 개발 환경 설정

### Crystal 설치

Noir는 Crystal로 작성되었습니다. 플랫폼별 설치 방법:

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### 기타 플랫폼
[Crystal 설치 가이드](https://crystal-lang.org/install/)를 참조하세요.

### 빌드 및 테스트

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

빌드:

```sh
shards build
# 바이너리는 ./bin/noir에 위치합니다
```

테스트 실행:

```sh
crystal spec

# 더 자세한 출력을 위해
crystal spec -v
```

### 린팅

`ameba`를 사용하여 코드 스타일을 검사합니다:

```sh
bin/ameba.cr
```

자동 수정:

```sh
bin/ameba.cr --fix
```

또는 `just` 사용:

```sh
just fix
```
