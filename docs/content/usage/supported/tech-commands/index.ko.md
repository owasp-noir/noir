+++
title = "기술 범위 관리"
description = "techs, only-techs, exclude-techs 플래그로 Noir가 스캔할 기술을 조절합니다."
weight = 3
sort_by = "weight"

+++

Noir는 코드에 쓰인 기술을 스스로 탐지합니다. 일부를 추가하거나, 범위를 좁히거나, 빼고 싶을 때 아래 플래그를 쓰세요.

## 플래그

*   `-t`, `--techs <TECHS>`: 자동 탐지된 기술에 더해 지정한 기술을 분석 대상에 추가합니다(쉼표로 구분, 예: `rails,django`).
*   `--only-techs <TECHS>`: 지정한 기술의 탐지기만 실행합니다(쉼표로 구분, 예: `rails,django`).
*   `--exclude-techs <TECHS>`: 탐지가 끝난 뒤 지정한 기술을 결과에서 뺍니다.
*   `noir list techs`: Noir가 지원하는 모든 기술을 보여줍니다.

세 플래그 모두 여러 번 쓸 수 있습니다. 기술 이름은 짧게 써도 됩니다. `rails`는 `ruby_rails`, `kemal`은 `crystal_kemal`에 대응합니다.

`--techs`와 `--only-techs`는 비슷해 보이지만 동작이 다릅니다. `--only-techs`는 실행할 탐지기를 제한하므로 스캔이 빨라지고 그 기술만 찾습니다. `--techs`는 탐지가 놓쳤더라도 그 기술의 분석기를 실행합니다. "이 기술만, 탐지되지 않았더라도 실행"하고 싶다면 둘을 함께 쓰세요.

### 특정 기술 포함

```bash
noir scan . --techs rails
```

### 자동 탐지를 특정 기술로 제한

```bash
noir scan . --only-techs rails
```

### 특정 기술 제외

```bash
noir scan . --exclude-techs express,koa
```

### 지원 기술 목록 보기

```bash
noir list techs
noir list techs -f json   # machine-readable
```