+++
title = "Noir 실행"
description = "Noir로 코드베이스를 스캔하고 출력을 설정하는 기본 명령어입니다."
weight = 3
sort_by = "weight"

+++

## 기본 스캔

현재 디렉토리 스캔:

```bash
noir -b .
```

하위 디렉토리 스캔:

```bash
noir -b ./my_app
```

![](./running.png)

## 도움말 보기

```bash
noir --help
```

## 지원되는 기술 확인

```bash
noir --list-techs
```

## 출력 형식

기본 출력은 표 형식입니다. 다른 형식:

### JSON 출력

```bash
noir -b . -f json
```

### YAML 출력

```bash
noir -b . -f yaml
```

### OpenAPI 명세

```bash
noir -b . -f oas3
```

## 로그 억제

```bash
noir -b . --no-log
```

## 상세 출력

```bash
noir -b . --verbose
```

## 출력 사용자 정의

### 파일 경로 포함

```bash
noir -b . --include-path
```

### 기술 정보 포함

```bash
noir -b . --include-techs
```

함께 사용:

```bash
noir -b . --include-path --include-techs
```