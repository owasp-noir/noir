+++
title = "Noir에 기여하기"
description = "OWASP Noir 프로젝트에 기여하는 방법을 알아보세요. 이 가이드는 개발 환경 설정, 프로젝트 빌드, 첫 번째 풀 리퀘스트 제출 방법에 대한 지침을 제공합니다."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir는 버그 수정, 기능 추가, 문서 개선 등 모든 기여를 환영합니다.

## 빠른 시작

1. **포크**: [저장소](https://github.com/owasp-noir/noir) 포크
2. **브랜치 생성**: `git checkout -b feature-name`
3. **변경 및 테스트**
4. **커밋**: 명확한 메시지 작성
5. **푸시**: `git push origin feature-name`
6. **PR 생성**: 설명 포함

자세한 내용은 [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)를 참조하세요.

## 개발 환경

### Crystal 설치

[Crystal 설치 가이드](https://crystal-lang.org/install/)를 따르세요.

### 설정, 빌드 및 테스트

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install    # 의존성 설치
shards build      # 바이너리: ./bin/noir
crystal spec      # 테스트 실행 (-v: 상세 출력)
```

### 린팅

```sh
ameba --fix       # 스타일 자동 수정
# 또는
just fix          # 포맷 및 수정
```