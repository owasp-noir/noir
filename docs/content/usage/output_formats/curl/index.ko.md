+++
title = "HTTP 클라이언트 명령어"
description = "Noir 스캔 결과에서 cURL, HTTPie, PowerShell 명령어를 생성합니다."
weight = 1
sort_by = "weight"

+++

발견된 엔드포인트를 바로 실행할 수 있는 HTTP 클라이언트 명령어로 변환합니다. `-u`로 base URL을 지정하면 경로 앞에 자동으로 붙여줍니다.

## cURL

[cURL](https://curl.se/)은 가장 널리 쓰이는 커맨드라인 HTTP 클라이언트입니다. 생성되는 명령어에는 `-i`(응답 헤더 포함), `-X`(HTTP 메서드), `-d`(요청 바디), `-H`(헤더), `--cookie`(쿠키) 등의 플래그가 적절히 들어갑니다.

```bash
noir -b . -f curl -u https://www.example.com
```

출력 예시
```bash
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
```

## HTTPie

[HTTPie](https://httpie.io/)는 cURL보다 직관적인 문법에 컬러 출력과 JSON 지원이 기본 내장된 HTTP 클라이언트입니다.

```bash
noir -b . -f httpie -u https://www.example.com
```

출력 예시
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

Windows 환경이라면 별도 도구 설치 없이 바로 쓸 수 있는 [Invoke-WebRequest](https://learn.microsoft.com/ko-kr/powershell/module/microsoft.powershell.utility/invoke-webrequest) 명령어를 생성합니다.

```bash
noir -b . -f powershell -u https://www.example.com
```

출력 예시
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```
