+++
title = "HTTP 클라이언트 명령어"
description = "Noir 스캔 결과에서 cURL, HTTPie, PowerShell 명령어를 생성합니다."
weight = 1
sort_by = "weight"

+++

발견된 엔드포인트를 테스트하기 위한 명령줄 HTTP 클라이언트 명령어를 생성합니다.

## cURL

cURL 명령어 생성:

```bash
noir -b . -f curl -u https://www.example.com
```

출력 예제:
```bash
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
```

## HTTPie

[HTTPie](https://httpie.io/) 명령어 생성:

```bash
noir -b . -f httpie -u https://www.example.com
```

출력 예제:
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

[Invoke-WebRequest](https://learn.microsoft.com/ko-kr/powershell/module/microsoft.powershell.utility/invoke-webrequest) 명령어 생성:

```bash
noir -b . -f powershell -u https://www.example.com
```

출력 예제:
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```