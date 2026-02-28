+++
title = "빌드 방법"
description = "개발 환경 설정, 소스에서 프로젝트 빌드, 테스트 실행 및 OWASP Noir에 기여하는 방법을 알아보세요."
weight = 1
sort_by = "weight"

+++

OWASP Noir는 커뮤니티 주도 프로젝트이며, 모든 종류의 기여를 환영합니다. 버그 수정, 새로운 기능 추가, 문서 개선 등 어떤 도움이든 크게 감사드립니다.

## 기여 방법

기여하는 가장 좋은 방법은 다음 단계를 따르는 것입니다:

1.  **저장소 포크**: GitHub에서 [Noir 저장소](https://github.com/owasp-noir/noir)의 자신만의 복사본을 만드는 것부터 시작하세요.
2.  **새 브랜치 생성**: 변경 사항을 위해 포크에서 새 브랜치를 생성하세요.
    ```sh
    git checkout -b your-feature-or-fix-name
    ```
3.  **변경 사항 적용**: 코드나 문서에 변경 사항을 적용하세요.
4.  **변경 사항 커밋**: 명확하고 설명적인 커밋 메시지와 함께 변경 사항을 커밋하세요.
5.  **변경 사항 푸시**: 변경 사항을 포크에 푸시하세요.
    ```sh
    git push origin your-feature-or-fix-name
    ```
6.  **풀 리퀘스트 생성**: 포크에서 메인 Noir 저장소로 풀 리퀘스트를 엽니다. 적용한 변경 사항에 대한 명확한 설명을 제공해 주세요.

더 자세한 가이드라인은 공식 [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) 파일을 참조하세요.

## 개발 환경 설정

코드에 기여하는 경우 로컬 개발 환경을 설정해야 합니다.

### Crystal 설치

Noir는 Crystal 프로그래밍 언어로 구축되었습니다. 주요 플랫폼에 대한 빠른 설치 방법은 다음과 같습니다:

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### 기타 플랫폼
다른 플랫폼의 경우 공식 [Crystal 설치 가이드](https://crystal-lang.org/install/)를 참조하세요.

### 빌드 및 테스트

Crystal이 설치되면 저장소를 클론하고 종속성을 설치할 수 있습니다:

```sh
# 포크 클론
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir

# 종속성 설치
shards install
```

프로젝트를 빌드하려면 다음을 실행하세요:

```sh
shards build
# 바이너리는 ./bin/noir에 위치합니다
```

유닛 및 기능 테스트를 실행하려면:

```sh
crystal spec

# 더 자세한 출력을 위해
crystal spec -v
```

### 린팅

코드 린팅에는 `ameba`를 사용합니다. 스타일 이슈를 확인하려면 다음을 실행하세요:

```sh
bin/ameba.cr
```

스타일 이슈를 자동으로 수정하려면 다음을 실행할 수 있습니다:

```sh
bin/ameba.cr --fix
```

또는 `just` 명령을 사용하여 린터를 실행할 수 있습니다:

```sh
just fix
```
