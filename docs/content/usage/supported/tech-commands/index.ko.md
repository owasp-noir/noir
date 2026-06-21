+++
title = "기술 범위 관리"
description = "techs 및 exclude-techs 플래그로 Noir 스캔 대상 기술을 제어합니다."
weight = 3
sort_by = "weight"

+++

스캔 시 특정 기술을 포함하거나 제외하여 관련 프레임워크에 집중하고 노이즈를 줄일 수 있습니다.

## 플래그

*   `--techs <TECHS>`: 자동 감지된 기술에 더해 지정한 기술을 분석 대상에 추가합니다 (쉼표로 구분, 예: `rails,django`).
*   `--only-techs <TECHS>`: 자동 감지를 지정한 기술 감지기로만 제한합니다 (쉼표로 구분, 예: `rails,django`).
*   `--exclude-techs <TECHS>`: 지정된 기술을 스캔에서 제외합니다.
*   `noir list techs`: Noir가 지원하는 모든 기술 목록을 표시합니다.

### 특정 기술 포함

```bash
noir scan . --techs rails
```

### 자동 감지를 특정 기술로 제한

```bash
noir scan . --only-techs rails
```

### 특정 기술 제외

```bash
noir scan . --exclude-techs express,koa
```

### 사용 가능한 기술 나열

```bash
noir list techs
```