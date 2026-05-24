+++
title = "추가 기능"
description = "Tagger는 엔드포인트에 컨텍스트 태그를 붙이고, Deliver는 결과를 다른 도구(Burp Suite, ZAP, Elasticsearch 등)로 보냅니다."
weight = 10
sort_by = "weight"

+++

엔드포인트 추출 외에도 Noir는 인벤토리를 다음 단계에서 어떻게 쓸지 좌우하는 두 가지 기능을 제공합니다:

*   **Tagger**: 엔드포인트와 파라미터에 컨텍스트 태그(예: `shadow`, `websocket`, 싱크 힌트)를 붙입니다. 코드 감사자(사람이든 LLM이든)가 먼저 살펴야 할 항목에 집중하도록 만들 때 유용합니다.
*   **Deliver**: 결과를 Burp Suite, ZAP, Elasticsearch 등으로 보내, 이미 운영 중인 파이프라인에 Noir 출력을 끼워 넣습니다.
