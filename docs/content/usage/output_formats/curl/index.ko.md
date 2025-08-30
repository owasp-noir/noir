+++
title = "HTTP 클라이언트 명령어"
description = "Noir 스캔 결과에서 cURL 및 HTTPie와 같은 인기 있는 HTTP 클라이언트용 실행 가능한 명령어를 직접 생성하는 방법을 알아보세요. 이를 통해 발견된 엔드포인트를 쉽게 테스트하고 상호작용할 수 있습니다."
weight = 1
sort_by = "weight"

[extra]
+++

Noir는 좋아하는 명령줄 HTTP 클라이언트용 명령어를 자동으로 생성할 수 있어 발견한 엔드포인트를 테스트하고 상호작용하기 시작하는 것이 매우 쉬워집니다. 이 기능은 코드 분석과 실제 테스트 간의 격차를 해소하는 좋은 방법입니다.

## cURL

엔드포인트에 대한 `curl` 명령어 목록을 생성하려면 `-f curl` 또는 `--format curl` 플래그를 사용하세요. 또한 Noir가 전체 요청 URL을 구성할 수 있도록 `-u` 플래그로 기본 URL을 제공해야 합니다.

```bash
noir -b . -f curl -u https://www.example.com
```

이렇게 하면 각 엔드포인트에 대해 하나씩, 올바른 HTTP 메서드, 헤더 및 매개변수가 포함된 `curl` 명령어 시리즈가 출력됩니다.

```bash
# 예제 출력
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
# ... 계속
```

## HTTPie

[HTTPie](https://httpie.io/)를 사용하는 것을 선호한다면 Noir가 이에 대한 명령어도 생성할 수 있습니다. `-f httpie` 플래그를 사용하고 다시 기본 URL을 제공하세요.

```bash
noir -b . -f httpie -u https://www.example.com
```

이렇게 하면 터미널에서 직접 실행할 수 있는 `http` 명령어 목록이 생성됩니다.

```bash
# 예제 출력
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
# ... 계속
```

이 기능을 사용하면 각 요청을 수동으로 구성할 필요 없이 빠르고 쉽게 엔드포인트 테스트를 시작할 수 있습니다.