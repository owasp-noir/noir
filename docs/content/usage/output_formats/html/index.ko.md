+++
title = "HTML 리포트"
description = "공격 표면 스캔 결과에 대한 포괄적이고 시각적인 HTML 보고서를 생성합니다."
weight = 3
sort_by = "weight"

+++

스캔 결과를 시각화하는 독립적이고 대화형인 HTML 파일을 생성합니다. 이해관계자와 공유하거나 공격 표면을 검토하는 데 적합합니다.

## 기본 사용법

```bash
noir -b . -f html -o report.html
```

### 주요 기능

- **대시보드 요약**: 전체 엔드포인트, 매개변수 및 패시브 스캔 결과에 대한 고수준 요약.
- **엔드포인트 세부 정보**: 발견된 모든 엔드포인트 목록(HTTP 메서드별 분류).
- **매개변수 분석**: 매개변수, 유형(쿼리, 폼, JSON 등) 및 값을 보여주는 상세 테이블.
- **패시브 스캔 결과**: 패시브 스캐닝이 활성화된 경우 설명, 심각도 및 코드 스니펫과 함께 결과가 표시됩니다.
- **소스 코드 링크**: 엔드포인트가 정의된 위치를 가리키는 파일 경로 및 줄 번호.

## 템플릿 사용자 정의

브랜딩이나 내부 보고 표준에 맞게 자체 템플릿을 제공할 수 있습니다.

### 템플릿 위치

Noir는 구성 디렉토리에서 `report-template.html` 파일을 찾습니다:

- **Linux/macOS**: `~/.config/noir/report-template.html`
- **Windows**: `%APPDATA%\noir\report-template.html`
- **Custom Home**: `NOIR_HOME`이 설정된 경우 `$NOIR_HOME/report-template.html`에서 찾습니다.

이 파일이 존재하면 내장 기본값 대신 사용됩니다.

### 플레이스홀더

템플릿에서 사용할 수 있는 플레이스홀더 (Noir가 생성된 콘텐츠로 대체):

| 플레이스홀더 | 설명 |
| :--- | :--- |
| `<%= noir_head %>` | 기본 CSS 및 메타데이터를 포함한 `<head>` 태그의 내용. |
| `<%= noir_header %>` | 제목과 로고가 포함된 헤더 섹션. |
| `<%= noir_summary %>` | 요약 대시보드(카운트를 보여주는 카드). |
| `<%= noir_endpoints %>` | 발견된 모든 엔드포인트를 나열하는 주요 섹션. |
| `<%= noir_passive_scans %>` | 패시브 스캔 결과를 나열하는 섹션. |
| `<%= noir_footer %>` | 바닥글 섹션. |

### 예제 템플릿

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <!-- 기본 스타일 및 스크립트 포함 -->
    <%= noir_head %>
    <style>
        /* 사용자 정의 스타일 추가 */
        body { background-color: #f0f2f5; }
        .company-header { padding: 20px; text-align: center; background: #333; color: #fff; }
    </style>
</head>
<body>
    <div class="company-header">
        <h1>My Company Security Report</h1>
    </div>

    <!-- 원래 헤더 -->
    <%= noir_header %>

    <main class="container">
        <!-- 요약 섹션 -->
        <%= noir_summary %>

        <h2>Detailed Findings</h2>
        
        <!-- 엔드포인트 목록 -->
        <%= noir_endpoints %>

        <!-- 패시브 스캔 결과 -->
        <%= noir_passive_scans %>
    </main>

    <%= noir_footer %>
</body>
</html>
```

이 파일을 `~/.config/noir/report-template.html`에 배치하면 이후 모든 보고서에 이 레이아웃이 사용됩니다.
