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
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | 그 언어의 소스 파일 집합과 경로별 필터. 언어당 하나. 순회 자체는 대부분 `FileScanEngine` 에서 옵니다 — `analyze` + `parallel_file_scan` 을 소유하며, 동시성은 `Analyzer#parallel_analyze` 가 담당합니다. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor*.cr` | 소스 내용을 파싱. 문자열(파일 내용) 을 받아 라우트 선언(method, path, location) 을 yield. 파일 I/O 없음, 프레임워크 특화 로직 없음. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | 프레임워크별 얇은 클래스. Extractor 에서 받은 라우트에 프레임워크별 파라미터 매핑, 필터, 특수 케이스를 적용. |

**Reference implementation**: [`src/analyzer/analyzers/javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr) + [`src/miniparsers/js_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/js_route_extractor.cr). Hono 는 이 분리를 따르기 때문에 얇게 유지됩니다. 세 책임을 한 클래스에 섞은 분석기와 비교해 보세요.

## 현재 커버리지

- **Language engines** (`engines/`): Specification, JavaScript/TypeScript, Go, Python, PHP, Rust, Ruby, Crystal, CFML, Scala, Swift, Perl, Elixir.
- **`FileScanEngine`** 은 그중 일곱 개(Crystal, Elixir, Perl, PHP, Rust, Scala, Swift) *아래* 에 있는 공유 베이스입니다. 각 엔진이 바이트 단위로 똑같이 복제해 갖고 있던 파일 순회 스켈레톤을 여기서 소유합니다.
- `java_engine.cr` 과 `kotlin_engine.cr` 은 파일 이름과 달리 **엔진이 아닙니다.** 공유 `self.test_path?` 하나를 노출하는 module 이고, 상속하는 분석기가 없습니다.
- **Route extractors** (`miniparsers/`): JavaScript(`js_route_extractor.cr` — Hono, Express, Fastify, Koa, NestJS, Restify, AdonisJS, Elysia, Hapi 등에서 사용) 와 Go/Java/Kotlin/Python 용 Tree-sitter 추출기. Go 와 Kotlin 은 umbrella `require` 뒤의 파트 파일 디렉터리로 나뉘어 있습니다 (`go_route_extractor_ts/`, `kotlin_route_extractor_ts/`).
- **의도적으로 엔진 밖**: 여러 단계를 조율하거나 자체 완결 추출을 가진 언어들 — CSharp, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua, Groovy, Scala Play, 그리고 Go 의 Chi/Httprouter/Fasthttp. `Analyzer` 를 직접 상속합니다.

## 두 가지 엔진 shape

모든 엔진이 `parallel_file_scan(&block)` 를 protected helper 로 노출합니다. 어댑터는 다음 중 하나를 선택합니다.

**Shape A. `analyze_file`** (단순, 순수 per-file):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # 파싱하고 엔드포인트 만들어 반환
  end
end
```

`FileScanEngine#analyze` 가 파일 순회를 돌리고 반환된 엔드포인트를 concat 합니다. 엔진은 `scan_target_files` 로 후보 목록을, `scan_accepts?` 로 선택적인 경로별 거부를 제공합니다. 대부분의 Php / Rust / Swift / Crystal / Elixir / Scala 분석기가 이 shape.

**Shape B. `analyze` 직접 오버라이드** (클로저 상태, pre/post-phase 필요):

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
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end
  end
end
```

`detector_for` 는 tech 이름을 한 번만 선언하고, `detect` 에 어떤 파일을 넘길지 결정하는 값싼 파일 게이트(`applicable?`) 를 생성합니다. 게이트 키는 `extensions:`, `basenames:`, `path_segments:` 입니다. `detect` 가 부수효과를 가진다면 — 예를 들어 `CodeLocator` 에 스펙 경로를 등록한다면 — `idempotent: false` 도 함께 넘겨야 첫 매칭 이후에도 계속 호출됩니다.

Detector 는 프로젝트의 후보 파일별로 한 번씩 실행됩니다. `true` 를 반환하면 해당 프레임워크가 존재한다고 표시되고 파이프라인이 매칭되는 분석기를 실행합니다.

## 새 프레임워크 추가하기

**Hertz (Go)** 를 예시로 단계별 안내. 실제 PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

`src/detector/detectors/{언어}/{프레임워크}.cr` 생성:

```crystal
require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
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
    analyzer_for "go_hertz"

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

- **언어 엔진을 상속**. `get_route_path`, `add_param_to_endpoint`, `collect_package_groups`, `resolve_public_dirs` 등을 별도 구현 없이 그대로 사용.
- **`analyzer_for` 로 tech 선언**. 이 한 줄이 등록의 전부입니다 — 3단계 참조.
- **재정의 가능한 메서드 오버라이드**. 프레임워크 파싱이 다르면 `get_static_path`, `get_route_path` 등 재정의 (Mux, GoZero 참조).
- **`parallel_file_scan` 사용**. 채널 + worker pool 을 재구현하지 말 것.
- **프레임워크가 실제 라우팅하는 verb만** 메서드 테이블에 나열. 특히 `QUERY`(RFC 10008)는 업스트림이 명시적으로 지원할 때만 추가 — 추측성 항목은 프레임워크가 405로 응답할 엔드포인트를 보고하게 됩니다. 와일드카드(`ANY`/`ALL`/`*`) 라우트에도 같은 정책이 적용됩니다: 공용 `WILDCARD_HTTP_METHODS`(`src/utils/http_symbols.cr`)든, 분석 시점에 자체 테이블로 `ANY`를 확장하는 analyzer 로컬 목록이든 `QUERY`를 추가하지 않습니다.

### 3. tech 메타데이터 선언

**수정해야 할 등록 목록은 없습니다.** 분석기와 detector 레지스트리는 클래스 자체에서 파생됩니다. `initialize_analyzers`(`src/analyzer/analyzer.cr`) 와 `build_detector_list`(`src/detector/detector.cr`) 가 각각 `all_subclasses` 를 훑어 `analyzer_for` / `detector_for` 에서 이름을 읽습니다. 두 목록 모두 예전에는 손으로 관리했고, 항목을 빠뜨리면 에러도 실패하는 스펙도 없이 그저 실행되지 않는 컴포넌트가 생겼습니다.

따라서 추가할 것은 카탈로그 항목 하나뿐이며, 분석기·디텍터와 같은 상대 경로에 새 파일로 만듭니다.

```crystal
# src/techs/catalog/go/hertz.cr
#
# 디렉터리는 언어, 파일명은 분석기 파일명과 동일하고, 상수는 그 파일명을
# 대문자화한 것입니다. `NoirTechs::TECHS` 는 `NoirTechs::Catalog` 아래 모든
# 상수에서 매크로로 파생되므로 append 할 목록이 없고, 두 사람이 프레임워크를
# 추가해도 같은 파일을 건드리지 않습니다.
module NoirTechs::Catalog::Go
  HERTZ = {
    :go_hertz => {
      :framework => "Hertz",
      :language  => "Go",
      :similar   => ["hertz", "go-hertz", "go_hertz", "cloudwego"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => { :query => true, :path => true, :body => true, :header => true, :cookie => true },
        :static_path => false,
        :websocket   => false,
      },
      # 선택 사항. 이 tech 가 지원하는 AI 컨텍스트 기능을 선언합니다.
      # CALLEE_SUPPORTED_TECHS 와 AI_CONTEXT_GUARD_SUPPORTED_TECHS 는
      # 손으로 나열하는 대신 이 플래그에서 파생됩니다.
      :context => { :callee => true },
    },
  }
end
```

`spec/unit_test/techs/registry_integrity_spec.cr` 이 세 축의 연결을 양방향으로 단언합니다. 모든 분석기와 detector 에 카탈로그 항목이 있어야 하고, 모든 카탈로그 항목은 분석기와 detector 양쪽으로 뒷받침되어야 합니다. 카탈로그 항목이 빠지면 런타임이 아니라 이 스펙에서 실패합니다.

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
just check                 # crystal tool format --check + ameba

# 수동 확인
./bin/noir -b spec/functional_test/fixtures/{언어}/{프레임워크}
```

## 새 언어 엔진 추가하기

같은 언어에서 2개 이상의 분석기가 파일 순회 패턴을 공유할 때 엔진을 추출합니다. **`FileScanEngine` 을 상속하세요** — 순회는 이미 거기에 있습니다. 새 엔진은 언어에 특화된 것만 선언합니다. 어떤 파일을 스캔할지, 무엇을 건너뛸지, 그리고 공유하는 라우트 합성 헬퍼입니다.

```crystal
# src/analyzer/engines/swift_engine.cr
require "../../models/analyzer"

require "./file_scan_engine"

module Analyzer::Swift
  abstract class SwiftEngine < FileScanEngine
    # 후보 파일. 모노레포 전체 `file_map` 을 걷는 대신 detector 가 만든
    # 확장자 인덱스를 쓰세요. 등록된 일반 파일이므로 경로마다
    # `File.exists?` / `File.directory?` 를 다시 볼 필요가 없습니다.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".swift")
    end

    # 선택적 경로별 거부. 절대 경로가 아니라 스캔 베이스 기준 상대 경로로
    # 판단해야 합니다. 절대 경로로 컨벤션 필터를 걸면 판단이 체크아웃
    # 위치에 넘어가서, 같은 트리인데 클론한 디렉터리에 따라 결과가
    # 달라집니다.
    protected def scan_accepts?(path : String) : Bool
      relative = base_relative_path(path)
      return false if relative.includes?("/Tests/")
      !relative.includes?("/.build/")
    end
  end
end
```

`FileScanEngine` 이 `analyze`(순회하며 경로마다 `analyze_file` 호출 후 concat), `abstract def analyze_file(path) : Array(Endpoint)` 계약, 그리고 커스텀 `analyze` 가 필요한 서브클래스를 위한 `parallel_file_scan` 을 제공합니다. 채널 + worker pool 을 다시 만들지 마세요. [#2465](https://github.com/owasp-noir/noir/pull/2465) 가 이를 hoist 하기 전까지 아홉 개 엔진이 바이트 단위로 똑같은 복사본을 각자 갖고 있었고, 손으로 복사하는 순간 그 중복이 되살아납니다.

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

정식 예시: [#1243](https://github.com/owasp-noir/noir/pull/1243) (Go `common.cr` split). 추출기가 한 파일을 넘어서면 그대로 키우지 말고 umbrella `require` 뒤의 파트 파일 디렉터리로 나누세요 — [`go_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/go_route_extractor_ts) 는 프레임워크 계열별로, [`kotlin_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/kotlin_route_extractor_ts) 는 관심사별로 나뉘어 있습니다.

## 실행 모델 참고

Noir 는 **single-threaded** 로 빌드됩니다 (`preview_mt` 미사용). `parallel_analyze` 는 OS 스레드가 아니라 cooperative Crystal fiber 를 spawn 합니다. 따라서 여러 fiber 에서 `result << endpoint`, `result.concat(...)` 는 안전한데, `Array#<<` 와 `#concat` 에 yield 지점이 없기 때문입니다. 모든 per-file 분석기가 result 배열에 Mutex 를 쓰지 않는 이유가 여기에 있고, 코드베이스 전반이 그렇게 일관되게 작성되어 있습니다. 나중에 MT 모드를 켜게 되면 동기화는 `parallel_analyze` 레이어에 한 번 추가하면 되는 일이지, 분석기마다 흩어 둘 일이 아닙니다.

#2353 에서 엔진들에 `@result_mutex` 와 `append_endpoint` 헬퍼가 추가되었다가 #2357 에서 다시 제거되었습니다. single-threaded 빌드에서는 발생할 수 없는 race 를 막고 있었고, 일부 엔진에만 적용되어 있었으며, 이 문서와 정면으로 어긋났기 때문입니다. Mutex 를 다시 넣으려 한다면 그 반복을 여는 셈입니다. MT 를 먼저 켜고, 동기화는 `parallel_analyze` 레이어에 한 번만 추가하세요.

## 다음에 볼 것

- Reference analyzer: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- 공유 파일 순회 베이스: [`engines/file_scan_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/file_scan_engine.cr)
- Engine + extractor 쌍: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor_ts.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor_ts.cr)
- Custom shape 예시: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (pre-phase + closure state)
- Framework-adapter-only 예시: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (엔진 리팩터링 이후 첫 프레임워크)
