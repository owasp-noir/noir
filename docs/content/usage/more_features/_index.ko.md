+++
title = "추가 기능"
description = "Tagger는 컨텍스트 태그를 붙이고, Diff 모드는 리비전 간 공격 표면을 비교하며, Deliver는 결과를 다른 도구(Burp Suite, ZAP, Elasticsearch 등)로 보냅니다."
weight = 10
sort_by = "weight"

+++

엔드포인트 추출 외에도 Noir는 인벤토리를 다음 단계에서 어떻게 쓸지 좌우하는 기능을 제공합니다:

*   **Tagger**: 엔드포인트와 파라미터에 컨텍스트 태그(예: `oauth`, `websocket`, `pii`, 그리고 파라미터 단위의 `sqli`·`idor` 같은 힌트)를 붙입니다. 코드 감사자(사람이든 LLM이든)가 먼저 살펴야 할 항목에 집중하도록 만들 때 유용합니다.
*   **Diff 모드**: 작업 트리를 다른 경로나 git 리비전(`--diff-ref`)과 비교해 추가·삭제·변경된 엔드포인트와 인증 손실을 보고하고, `--fail-on`으로 CI를 실패시킬 수 있습니다. [Diff 모드로 코드 비교하기](@/usage/more_features/diff/index.ko.md)를 참고하세요.
*   **Deliver**: 결과를 Burp Suite, ZAP, Elasticsearch 등으로 보내, 이미 운영 중인 파이프라인에 Noir 출력을 끼워 넣습니다.
