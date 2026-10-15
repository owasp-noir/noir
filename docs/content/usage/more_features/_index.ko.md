+++
title = "추가 기능"
description = "태거는 컨텍스트 태그를 붙이고, Diff 모드는 리비전 간 공격 표면을 비교하며, Deliver는 결과를 다른 도구(Burp Suite, ZAP, Elasticsearch 등)로 보냅니다."
weight = 10
sort_by = "weight"

+++

Noir는 엔드포인트를 찾는 것 말고도 태그를 붙이고, 버전 간에 비교하고, 다른 도구로 보낼 수 있습니다.

*   **태거**: 엔드포인트와 파라미터에 컨텍스트 태그(예: `oauth`, `websocket`, `pii`, 그리고 파라미터 단위의 `sqli`·`idor` 같은 힌트)를 붙입니다. 리뷰어(사람이든 LLM이든)가 무엇부터 볼지 고르는 데 도움이 됩니다.
*   **Diff 모드**: 작업 트리를 다른 경로나 git 리비전(`--diff-ref`)과 비교해 추가·삭제·변경된 엔드포인트와 사라진 인증을 보고하고, `--fail-on`으로 CI를 실패시킬 수 있습니다. [Diff 모드로 코드 비교하기](@/usage/more_features/diff/index.ko.md)를 참고하세요.
*   **Deliver**: 결과를 Burp Suite, ZAP, Elasticsearch, 웹훅으로 보내, 이미 쓰고 있는 파이프라인에 Noir를 붙입니다.
