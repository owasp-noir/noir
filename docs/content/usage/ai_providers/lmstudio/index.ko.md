+++
title = "LM Studio와 함께 Noir 사용하기"
description = "Noir를 LM Studio와 통합하여 로컬 언어 모델로 코드 분석을 수행하는 방법입니다."
weight = 3
sort_by = "weight"

+++

[LM Studio](https://lmstudio.ai)를 사용하면 로컬에서 언어 모델을 실행하여 비공개 코드 분석을 수행할 수 있습니다.

## 설정

1.  **LM Studio 설치**: [공식 웹사이트](https://lmstudio.ai)에서 다운로드하세요.
2.  **로컬 서버 시작**: LM Studio를 열고 모델을 선택한 다음 "Local Server" 탭에서 "Start Server"를 클릭하세요.

    ![](./lmstudio.png)

## 사용 방법

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=lmstudio \
     --ai-model <MODEL_NAME>
```

`<MODEL_NAME>`을 LM Studio에서 서빙 중인 모델 이름으로 바꾸세요.
