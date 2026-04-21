+++
title = "분석기 아키텍처"
description = "Noir의 detector, language engine, route extractor, framework adapter 가 어떻게 맞물리는지, 그리고 새 분석기를 어떻게 추가하는지."
weight = 5
sort_by = "weight"

+++

Noir 는 프로젝트를 두 단계로 스캔합니다. **Detector** 가 어떤 프레임워크가 존재하는지 판단하고, **Analyzer** 가 감지된 프레임워크별로 엔드포인트를 추출합니다. 이 페이지는 분석기 쪽 구조와 새 프레임워크 추가 방법을 설명합니다.

## 파이프라인 개요

```
프로젝트 파일
      │
      ▼
  Detector         ──►  "이 프로젝트는 go_gin, go_hertz, ... 를 사용"
      │
      ▼
  Analyzer         ──►  Endpoint 리스트 (url, method, params, details)
      │
      ▼
  Optimizer, Taggers, Passive scan, Output formatter
```

Detector 는 manifest 파일(`go.mod`, `package.json`, `Gemfile` 등) 에 대한 간단한 매칭으로 boolean 을 반환합니다. Analyzer 는 본격 작업(소스 트리 순회, 라우트 선언 파싱, 파라미터 추출) 을 담당합니다.

## 3-layer 분석기

모든 분석기는 세 레이어로 구성됩니다. **Framework adapter 는 파일을 열거나 파싱을 재구현하지 않는다** 는 것이 엄격한 규칙입니다.

| Layer | 위치 | 책임 |
|---|---|---|
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | 파일 순회, 동시성(`parallel_analyze`), 채널 설정, 경로별 에러 핸들링. 언어당 하나. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor.cr` | 소스 내용을 파싱. 문자열(파일 내용) 을 받아 라우트 선언(method, path, location) 을 yield. 파일 I/O 없음, 프레임워크 특화 로직 없음. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | 프레임워크별 얇은 클래스. Extractor 에서 받은 라우트에 프레임워크별 파라미터 매핑, 필터, 특수 케이스를 적용. |

**Reference implementation**: [`src/analyzer/analyzers/javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr) + [`src/miniparsers/js_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/js_route_extractor.cr). Hono 는 이 분리를 따르기 때문에 ~205줄입니다. 세 책임을 한 클래스에 섞은 분석기는 500–800줄로 커집니다.

## 현재 커버리지

- **Language engines** (`engines/`): PHP, Ruby, Rust, Elixir, Swift, Crystal, Scala, JavaScript/TypeScript, Python, Go.
- **Route extractors** (`miniparsers/`): JavaScript (Hono, Express, Fastify, Koa, NestJS, Restify, TypeScript NestJS 에서 사용) + Go (8개 분석기에서 사용).
- **의도적으로 엔진 밖**: CSharp 의 두 orchestrator, Scala Play (multi-phase 흐름이라 per-file 스캔 안 맞음), Go 의 Chi/Httprouter/Fasthttp (자체 완결 추출). `Analyzer` 를 직접 상속.
- Python, Kotlin, Java 는 parser 는 있지만 route extractor 층이 아직 없음 — 후속 작업.

## 두 가지 엔진 shape

모든 엔진이 `parallel_file_scan(&block)` 를 protected helper 로 노출합니다. 어댑터는 다음 중 하나를 선택합니다.

**Shape A — `analyze_file`** (단순, 순수 per-file):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # 파싱하고 엔드포인트 만들어 반환
  end
end
```

엔진의 기본 `analyze` 가 파일 순회를 돌리고 반환된 엔드포인트를 concat 합니다. 대부분의 Php / Rust / Swift / Crystal / Elixir / Scala 분석기가 이 shape.

**Shape B — `analyze` 직접 오버라이드** (클로저 상태, pre/post-phase 필요):

```crystal
class MyFramework < JavascriptEngine
  def analyze
    result = [] of Endpoint
    static_dirs = [] of Hash(String, String)

    parallel_file_scan do |path|
      # ... result 에 엔드포인트 추가, static_dirs 수집
    end

    process_static_dirs(static_dirs, result)  # post-pass
    result
  end
end
```

스캔 중 로컬 상태(뮤텍스, dedup set) 가 필요하거나 후처리 단계가 필요할 때 사용. Express, Hono, Rails, Amber 가 예시.

## Detector shape

Detector 는 대체로 한 줄짜리 매칭입니다.

```crystal
# src/detector/detectors/go/hertz.cr
module Detector::Go
  class Hertz < Detector
    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end

    def set_name
      @name = "go_hertz"
    end
  end
end
```

Detector 는 프로젝트의 후보 파일별로 한 번씩 실행됩니다. `true` 를 반환하면 해당 프레임워크가 존재한다고 표시되고 파이프라인이 매칭되는 분석기를 실행합니다.

## 새 프레임워크 추가하기

**Hertz (Go)** 를 예시로 단계별 안내. 실제 PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

`src/detector/detectors/{언어}/{프레임워크}.cr` 생성:

```crystal
require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end

    def set_name
      @name = "go_hertz"
    end
  end
end
```

### 2. Analyzer

`src/analyzer/analyzers/{언어}/{프레임워크}.cr` 생성. 언어 엔진을 상속:

```crystal
require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    HTTP_METHODS_EXPANDED = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    def analyze
      public_dirs = [] of Hash(String, String)
      package_groups, file_lines_cache = collect_package_groups

      parallel_file_scan do |path|
        lines = file_lines_cache[path]? || File.read_lines(path, encoding: "utf-8", invalid: :skip)
        groups = groups_for_directory(package_groups, File.dirname(path))
        # ... 라인별 라우트 + 파라미터 추출. 엔진을 거쳐 GoRouteExtractor 로 위임.
      end

      resolve_public_dirs(public_dirs)
      result
    end
  end
end
```

핵심 포인트:

- **언어 엔진을 상속**. `get_route_path`, `add_param_to_endpoint`, `collect_package_groups`, `resolve_public_dirs` 등을 무료로 사용 가능.
- **재정의 가능한 메서드 오버라이드**. 프레임워크 파싱이 다르면 `get_static_path`, `get_route_path` 등 재정의 (Mux, GoZero 참조).
- **`parallel_file_scan` 사용**. 채널 + worker pool 을 재구현하지 말 것.

### 3. 세 곳에 등록

```crystal
# src/analyzer/analyzer.cr
{"go_hertz", Go::Hertz},

# src/detector/detector.cr
Go::Hertz,

# src/techs/techs.cr
:go_hertz => {
  :framework => "Hertz",
  :language  => "Go",
  :similar   => ["hertz", "go-hertz", "cloudwego"],
  :supported => {
    :endpoint => true,
    :method   => true,
    :params   => { :query => true, :path => true, :body => true, :header => true, :cookie => true },
  },
},
```

### 4. Fixture

`spec/functional_test/fixtures/{언어}/{프레임워크}/` 에 최소 앱 생성:

```
spec/functional_test/fixtures/go/hertz/
├── go.mod            # detector 가 매칭할 import 라인
├── main.go           # 중요한 라우트/파라미터 패턴 커버
└── public/           # (옵션) static 파일 감지 테스트용
    └── index.html
```

Fixture 는 현실적 패턴(path param, query/form/header/cookie, 라우트 그룹, static, 프레임워크 특화 관용구) 을 커버해야 합니다. Hertz 의 `.Any` 가 모든 HTTP 메서드로 확장되는 것, Flask 의 blueprint 같은 것들. 모두 다 넣으려 하지 말고 실제 버그가 나타날 때 케이스 추가.

### 5. Spec

`spec/functional_test/testers/{언어}/{프레임워크}_spec.cr` 생성:

```crystal
require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  # ... 등등
]

FunctionalTester.new("fixtures/go/hertz/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
```

테스터가 검증하는 것:

- Detector 가 정확히 1개의 tech 를 찾는지.
- Analyzer 가 정확히 N개의 엔드포인트를 생성하는지 (`expected_endpoints.size` 와 일치).
- 각 expected 엔드포인트에 대해 URL + method 매칭되는 엔드포인트가 출력에 존재하는지.
- 각 expected 파라미터에 대해 `name + param_type` 매칭이 해당 엔드포인트에 붙어있는지.

### 6. 검증

```bash
just build                 # 깔끔하게 컴파일
just test                  # unit + functional spec 통과
crystal tool format --check
crystal run lib/ameba/bin/ameba.cr

# 수동 확인
./bin/noir -b spec/functional_test/fixtures/{언어}/{프레임워크}
```

## 새 언어 엔진 추가하기

같은 언어에서 2개 이상의 분석기가 파일 순회 패턴을 공유할 때 엔진을 추출합니다. `SwiftEngine` 이 템플릿:

```crystal
# src/analyzer/engines/swift_engine.cr
require "../../models/analyzer"

module Analyzer::Swift
  abstract class SwiftEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)
        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".swift"

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end
  end
end
```

엔진을 추가할 때는 같은 PR 에서 기존 분석기를 상속하도록 마이그레이션하세요. 예시 PR: [#1236](https://github.com/owasp-noir/noir/pull/1236) (Elixir), [#1237](https://github.com/owasp-noir/noir/pull/1237) (Swift), [#1238](https://github.com/owasp-noir/noir/pull/1238) (Crystal).

## Route extractor (L1) 추가하기

같은 언어에서 2개 이상의 분석기가 단순 파일 순회가 아닌 **실제 파싱 로직** 을 공유할 때 route extractor 모듈을 `src/miniparsers/{lang}_route_extractor.cr` 에 추출합니다. 순수 함수, `Analyzer` 의존성 없음:

```crystal
module Noir::MyLangRouteExtractor
  extend self

  def extract_route_path(line : String, groups : Array(...)) : String
    # 순수 파싱
  end
end
```

엔진은 얇은 인스턴스 메서드 위임을 노출해 어댑터가 프레임워크별 파싱이 다를 때 오버라이드할 수 있게 합니다:

```crystal
class MyLangEngine < Analyzer
  def get_route_path(line, groups)
    Noir::MyLangRouteExtractor.extract_route_path(line, groups)
  end
end
```

정식 예시: [#1243](https://github.com/owasp-noir/noir/pull/1243) (Go `common.cr` split).

## 실행 모델 참고

Noir 는 **single-threaded** 로 빌드됩니다 (`preview_mt` 미사용). `parallel_analyze` 는 OS 스레드가 아니라 cooperative Crystal fiber 를 spawn 합니다. 따라서 여러 fiber 에서 `result << endpoint`, `result.concat(...)` 은 안전합니다 — `Array#<<` 와 `#concat` 에 yield 지점이 없기 때문. 모든 per-file 분석기가 result 배열에 Mutex 를 쓰지 않는 것이 그 이유이며, 코드베이스 전반이 그렇게 일관됩니다. 나중에 MT 모드를 켜게 되면 동기화는 `parallel_analyze` 레이어에 한 번 추가해야 하는 일이지, 분석기마다 흩어져 있을 일이 아닙니다.

## 다음에 볼 것

- Reference analyzer: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- Engine + extractor 쌍: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor.cr)
- Custom shape 예시: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (pre-phase + closure state)
- Framework-adapter-only 예시: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (엔진 리팩터링 이후 첫 프레임워크)
