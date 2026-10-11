+++
title = "분석기 아키텍처"
description = "Noir의 detector, language engine, route extractor, framework adapter가 어떻게 맞물리는지, 그리고 새 분석기를 어떻게 추가하는지."
weight = 5
sort_by = "weight"

+++

Noir는 프로젝트를 두 단계로 스캔합니다. 먼저 **detector**가 어떤 프레임워크가 있는지 판단하고, 이어서 **analyzer**가 감지된 프레임워크마다 엔드포인트를 추출합니다. 이 페이지에서는 분석기 쪽 구조와 새 프레임워크를 추가하는 방법을 설명합니다.

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

Detector는 매니페스트 파일(`go.mod`, `package.json`, `Gemfile` 등)을 가볍게 매칭해 boolean을 반환합니다. 무거운 작업은 analyzer가 맡습니다. 소스 트리를 돌고, 라우트 선언을 파싱하고, 파라미터를 추출합니다.

## 3-layer 분석기

모든 분석기는 세 레이어로 이뤄집니다. 레이어는 분리해서 유지하세요. framework adapter는 파일을 직접 열거나 파싱을 다시 구현하면 안 됩니다.

| Layer | 위치 | 책임 |
|---|---|---|
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | 그 언어의 소스 파일 집합, 경로별 필터, worker pool, 콘텐츠 캐시. 언어당 하나입니다. 엔진 8개는 순회 자체를 `FileScanEngine`에서 가져옵니다. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor*.cr` | 소스 내용을 파싱합니다. 문자열(파일 내용)을 받아 라우트 선언(method, path, location)을 yield합니다. 파일 I/O도, 프레임워크 전용 규칙도 없습니다. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | 프레임워크별 얇은 클래스입니다. extractor가 넘긴 라우트에 프레임워크별 파라미터 매핑, 필터, 특수 케이스를 적용합니다. |

이 규칙 중 파일 순회 부분은 `spec/unit_test/analyzer/layering_boundary_spec.cr`가 강제합니다. `src/analyzer/analyzers/` 아래에서 `Dir.glob`, `Dir.children`, `Dir.each_child`를 쓰면 테스트가 실패합니다. 파일 목록은 엔진이나 detector가 만든 인덱스(`get_files_by_extension`, `CodeLocator#files_by_basename`)에서 받으세요. 디렉터리를 직접 돌면 서브트리 가지치기, `--exclude-path`, 미디어 필터, 콘텐츠 캐시를 모두 건너뜁니다.

**참고 구현.** 아직 전체 모델을 혼자 보여주는 분석기는 없습니다. 레이어마다 다른 파일을 참고하세요.

- **순회 (L0)**: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)는 `JavascriptEngine`을 상속하고 `parallel_file_scan`으로 순회합니다. 그래서 worker pool, 콘텐츠 캐시, test/vendor 필터를 따로 구현하지 않습니다. 본문은 따라 하지 마세요. extractor 호출 옆에 자체 정규식 패스가 아직 남아 있습니다.
- **본문 (L1 → L2)**: [`javascript/hapi.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hapi.cr)는 50줄 정도입니다. `Noir::TreeSitterHapiExtractor.extract_routes`를 호출하고 결과를 `Param`으로 옮기는 일만 합니다. `javascript/elysia.cr`, `javascript/adonisjs.cr`, `kotlin/http4k.cr`, `java/spark.cr`도 같은 모양입니다. 순회 방식은 따라 하지 마세요. 이 파일들은 `Analyzer`를 직접 상속하고 `all_files`를 스스로 돕니다.

## 현재 커버리지

- **Language engines** (`engines/`): Specification, JavaScript/TypeScript, Go, Python, PHP, Rust, Ruby, Crystal, CFML, Scala, Swift, Perl, C, Elixir.
- **`FileScanEngine`**은 그중 8개(C, Crystal, Elixir, Perl, PHP, Rust, Scala, Swift) 아래에 있는 공용 베이스입니다. 예전에 엔진마다 복사본을 들고 있던 `analyze` + `parallel_file_scan` 골격을 여기서 관리합니다.
- `java_engine.cr`과 `kotlin_engine.cr`은 파일 이름과 달리 엔진이 **아닙니다**. 상속하는 분석기가 없습니다. `KotlinEngine`은 공용 `self.test_path?`만 제공합니다. `JavaEngine`은 JVM 어댑터가 공용 헬퍼(JAX-RS 인덱스, Spring/Micronaut/Quarkus 설정 리더)를 쓰려고 `include`하는 mixin이기도 합니다. `PlayRouteSupport`와 `CliEndpointSupport`도 같은 종류의 mixin입니다.
- **Route extractors** (`miniparsers/`):
  - JavaScript: `js_route_extractor.cr`. Express, Fastify, Hono, Koa, Restify는 `JSRouteExtractor.extract_routes`에서 라우트를 받습니다. NestJS, Next.js, Nuxt 등은 헬퍼만 씁니다.
  - Go, Java, Kotlin, Python용 Tree-sitter 추출기. Go와 Kotlin은 umbrella `require` 뒤에 파트 파일을 둔 디렉터리 형태입니다(`go_route_extractor_ts/`, `kotlin_route_extractor_ts/`).
  - 프레임워크 전용 Tree-sitter 추출기: AdonisJS, Elysia, Hapi, http4k, JAX-RS, Micronaut, Ktor 등.
- **엔진 밖에 있는 분석기**: CSharp, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua, Groovy, Scala Play, 그리고 Go의 Chi, Httprouter, Fasthttp, Kratos. 여러 단계를 조율하거나 추출 로직이 자체로 완결되어 있어서 `Analyzer`를 직접 상속합니다.

## 엔진별 순회 헬퍼

모든 엔진이 공유하는 순회 API는 하나가 아닙니다. 어댑터를 쓰기 전에 해당 언어 엔진이 무엇을 제공하는지 확인하세요.

- **`FileScanEngine` 기반 엔진** (C, Crystal, Elixir, Perl, PHP, Rust, Scala, Swift): 엔진이 `scan_target_files`로 후보 목록을, `scan_accepts?`로 경로별 거부(선택)를 제공합니다. 어댑터는 `analyze_file`을 구현합니다(아래 Shape A).
- **JavaScript, Ruby 엔진**: `parallel_file_scan`을 직접 정의하고 `scan_target_files`는 없습니다. 어댑터는 `analyze`를 오버라이드하고 `parallel_file_scan`을 호출합니다(아래 Shape B).
- **언어 전용 이터레이터**: `PythonEngine`은 `python_source_files` / `each_python_source` / `parallel_python_sources`, `SpecificationEngine`은 `each_spec_file` / `each_spec_file_with_details`, `CfmlEngine`은 `cfml_components` / `cfml_pages`를 제공합니다. `GoEngine`은 `read_package_file_contents`와 `collect_*` 헬퍼로 패키지 전체 내용을 넘겨주고, 어댑터는 `parallel_analyze`로 순회합니다.
- **엔진 없음**: 어댑터가 `Analyzer`를 상속하고 `scan_files(files, &block)`를 씁니다. 위의 모든 엔진도 결국 이 공용 골격을 거칩니다.

**Shape A. `analyze_file`** (단순한 파일별 처리):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # 파싱하고 엔드포인트 만들어 반환
  end
end
```

`FileScanEngine#analyze`가 순회를 돌리고, 반환된 엔드포인트를 입력 순서대로 합칩니다. PHP, Rust, Swift, Crystal, Elixir, Scala 분석기 대부분이 이 방식입니다.

**Shape B. `analyze` 직접 오버라이드** (파일 간 상태, 전처리·후처리 단계가 필요할 때):

```crystal
class MyFramework < JavascriptEngine
  def analyze
    result = [] of Endpoint
    static_dirs = [] of Hash(String, String)

    parallel_file_scan do |path|
      # ... result 에 엔드포인트 추가, static_dirs 수집
    end

    process_js_static_dirs(static_dirs, result)  # post-pass
    result
  end
end
```

여러 파일에 걸친 상태나 후처리 단계가 필요할 때 씁니다. Express, Hono, Rails, Amber가 예입니다. worker 사이에서 상태를 공유하기 전에 이 페이지 끝의 실행 모델 참고를 먼저 읽으세요.

## Detector 모양

Detector는 대부분 한 줄짜리 매칭입니다.

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

`detector_for`는 tech 이름을 한 번 선언하고, 어떤 파일을 `detect`에 넘길지 정하는 가벼운 파일 게이트(`applicable?`)를 생성합니다. 게이트 키는 `extensions:`, `basenames:`, `path_segments:`입니다. `detect`에 부수효과가 있다면(예: `CodeLocator`에 스펙 경로 등록) `idempotent: false`도 넘기세요. 그래야 첫 매칭 뒤에도 계속 호출됩니다.

Detector는 후보 파일마다 한 번씩 실행됩니다. `true`를 반환하면 그 프레임워크가 있다고 표시되고, 파이프라인이 매칭되는 분석기를 실행합니다.

## 새 프레임워크 추가하기

**Hertz (Go)**를 예로 들어 단계별로 설명합니다. 실제 PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

`src/detector/detectors/{language}/{framework}.cr`을 만듭니다.

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

`spec/unit_test/detector/{language}/{framework}_spec.cr`에 유닛 스펙도 추가하세요. 필수입니다. 스펙이 없는 detector가 있으면 `spec/unit_test/techs/detector_coverage_spec.cr`가 실패합니다.

### 2. Analyzer

`src/analyzer/analyzers/{language}/{framework}.cr`을 만들고 언어 엔진을 상속합니다. Hertz는 Gin과 라우팅 방식이 같아서 구조 대부분을 Gin과 공유합니다.

```crystal
require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    analyzer_for "go_hertz"

    HTTP_METHODS_EXPANDED = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]
    IMPORT_MARKER         = "github.com/cloudwego/hertz"

    def analyze
      public_dirs = [] of Hash(String, String)
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)

      parallel_analyze(get_files_by_extension(".go")) do |path|
        content = file_contents[path]? || read_file_content(path)
        cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
        routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle")
        # ... 라우트를 엔드포인트로 변환한 뒤 라인별 파라미터 추출
      end

      resolve_public_dirs(public_dirs)
      result
    end
  end
end
```

핵심:

- **언어 엔진을 상속하세요** (여기서는 `GoEngine`). `collect_package_groups_ts`, `ts_groups_for_directory`, `add_param_to_endpoint`, `resolve_public_dirs`를 그대로 쓸 수 있습니다.
- **`analyzer_for`로 tech를 선언하세요**. 이 한 줄이 등록의 전부입니다(3단계 참고). 빠뜨리면 컴파일 에러가 납니다.
- **라우트 파싱은 공용 extractor에 맡기세요** (`Noir::TreeSitterGoRouteExtractor`). 프레임워크 라우팅이 다르면 직접 다시 파싱하지 말고 extractor 인자(예: `handle_method:`)나 전용 진입점으로 조정하세요(Mux, GoZero 참고).
- **엔진의 순회 헬퍼를 쓰세요** (Go는 `parallel_analyze(get_files_by_extension(".go"))`, 다른 언어는 `parallel_file_scan`이나 `analyze_file`). 채널과 worker pool을 다시 만들지 마세요.
- **프레임워크가 실제로 라우팅하는 verb만** 메서드 테이블에 넣으세요. 특히 `QUERY`(RFC 10008)는 업스트림이 명시적으로 지원할 때만 추가합니다. 추측으로 넣으면 프레임워크가 405로 응답할 엔드포인트를 보고하게 됩니다. 와일드카드(`ANY`/`ALL`/`*`) 라우트도 같습니다. 공용 `WILDCARD_HTTP_METHODS`(`src/utils/http_symbols.cr`)에도, 분석 시점에 `ANY`를 자체 테이블로 펼치는 분석기 로컬 목록에도 `QUERY`를 추가하지 마세요.

### 3. tech 메타데이터 선언

**수정할 등록 목록은 없습니다.** 분석기와 detector 레지스트리는 클래스에서 바로 만들어집니다. `initialize_analyzers`(`src/analyzer/analyzer.cr`)와 `build_detector_list`(`src/detector/detector.cr`)가 각각 `all_subclasses`를 훑어 `analyzer_for` / `detector_for`에서 이름을 읽습니다. 예전에는 두 목록을 손으로 관리했고, 항목을 빠뜨려도 에러나 실패하는 스펙 없이 그냥 실행되지 않는 컴포넌트가 생겼습니다.

남은 일은 카탈로그 항목 하나입니다. 분석기, detector와 같은 상대 경로에 새 파일로 만듭니다.

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
      :context => { :callee => true, :guards => true },
    },
  }
end
```

`spec/unit_test/techs/registry_integrity_spec.cr`가 세 요소의 연결을 양방향으로 검사합니다. 모든 분석기와 detector에 카탈로그 항목이 있어야 하고, 모든 카탈로그 항목에는 분석기와 detector가 둘 다 있어야 합니다. 카탈로그 항목이 빠지면 런타임이 아니라 이 스펙에서 실패합니다.

### 4. Fixture

`spec/functional_test/fixtures/{language}/{framework}/`에 최소한의 앱을 만듭니다.

```
spec/functional_test/fixtures/go/hertz/
├── go.mod            # detector 가 매칭할 import 라인
├── main.go           # 중요한 라우트/파라미터 패턴 커버
└── public/           # (옵션) static 파일 감지 테스트용
    └── index.html
```

Fixture에는 현실적인 패턴을 넣으세요. path param, query/form/header/cookie, 라우트 그룹, static 서빙, 프레임워크 고유 관용구(Hertz의 `.Any`는 모든 HTTP 메서드로 펼쳐지고, Flask에는 blueprint가 있는 식) 등입니다. 전부 넣으려 하지 말고, 실제 버그가 나올 때마다 케이스를 추가하세요.

### 5. Spec

`spec/functional_test/testers/{language}/{framework}_spec.cr`을 만듭니다.

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

테스터는 다음을 확인합니다.
- detector가 tech를 정확히 1개(내 프레임워크) 찾는지.
- analyzer가 엔드포인트를 정확히 N개(`expected_endpoints.size`) 만드는지.
- 기대한 엔드포인트마다 URL과 method가 같은 엔드포인트가 출력에 있는지.
- 기대한 파라미터마다 `name`과 `param_type`이 같은 파라미터가 그 엔드포인트에 붙어 있는지.

### 6. 검증

```bash
just build                 # 깔끔하게 컴파일
just test                  # unit + functional spec 통과
just check                 # crystal tool format --check + ameba

# 수동 확인
./bin/noir scan spec/functional_test/fixtures/{lang}/{framework}
```

## 다른 컴포넌트

출력 형식과 tagger도 같은 방식으로 등록합니다. 클래스에 어노테이션을 달면 되고, 수정할 목록은 없습니다.

- **출력 형식**: `src/output_builder/{format}.cr`을 만들고 클래스에 `@[Noir::OutputFormat(name: "{format}", description: "…", order: 40)]`를 답니다. `src/output_builder/formats.cr`가 여기서 `-f` 도움말, `noir list formats`, 렌더링 디스패치를 만듭니다. `spec/unit_test/output_builder/{format}_spec.cr`도 추가하세요.
- **Tagger**: `src/tagger/taggers/{name}.cr`(프레임워크 인증 tagger라면 `FrameworkTagger`를 상속해 `src/tagger/framework_taggers/{language}/{name}.cr`)을 만들고 `@[Noir::TaggerFor(key: "{name}", name: "…", desc: "…", order: 180)]`를 답니다. `key`는 `--use-taggers`에 넣는 값이 됩니다. `order`는 tagger 실행 순서, 즉 태그가 붙는 순서를 정하므로 번호를 다시 매기지 말고 뒤에 새 값을 붙이세요. 어노테이션을 빠뜨려도 컴파일 에러는 나지 않지만 `registry_integrity_spec.cr`가 실패하면서 클래스 이름을 알려줍니다. `spec/unit_test/tagger/` 아래에 스펙을 추가하세요.

## 새 언어 엔진 추가하기

한 언어에서 분석기 2개 이상이 같은 파일 순회 패턴을 쓰면 엔진으로 뽑아내세요. **`FileScanEngine`을 상속하세요.** 순회는 이미 거기 있습니다. 새 엔진은 언어 고유한 것만 선언합니다. 어떤 파일을 스캔할지, 무엇을 건너뛸지, 공용 라우트 조합 헬퍼 정도입니다.

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

`FileScanEngine`은 `analyze`(순회하며 경로마다 `analyze_file`을 부르고 입력 순서대로 합침), `abstract def analyze_file(path) : Array(Endpoint)` 계약, 그리고 커스텀 `analyze`가 필요한 서브클래스를 위한 `parallel_file_scan` / `ordered_file_scan`을 제공합니다. 채널과 worker pool을 다시 만들지 마세요. [#2465](https://github.com/owasp-noir/noir/pull/2465)에서 공용으로 올리기 전에는 엔진 9개가 똑같은 복사본을 각자 갖고 있었고, 직접 만들면 그 중복이 다시 생깁니다.

엔진을 추가할 때는 같은 PR에서 기존 분석기들도 그 엔진을 상속하도록 옮기세요. 예시: [#1236](https://github.com/owasp-noir/noir/pull/1236) (Elixir), [#1237](https://github.com/owasp-noir/noir/pull/1237) (Swift), [#1238](https://github.com/owasp-noir/noir/pull/1238) (Crystal).

## Route extractor (L1) 추가하기

한 언어에서 분석기 2개 이상이 파일 순회가 아닌 실제 파싱 로직을 공유하면, 그 로직을 `src/miniparsers/` 아래 route extractor로 옮기세요. 순수하게 유지합니다. 소스 내용을 받아 라우트를 반환하고, `Analyzer` 의존성도 파일 I/O도 두지 않습니다.

```crystal
module Noir::MyLangRouteExtractor
  extend self

  record Route, method : String, path : String, line : Int32

  def extract_routes(content : String) : Array(Route)
    # 순수 파싱
  end
end
```

어댑터는 extractor를 직접 호출하고 결과를 엔드포인트로 옮깁니다. `hapi.cr`가 `Noir::TreeSitterHapiExtractor.extract_routes(content, include_callee)`를 쓰는 방식과 같습니다. 그 언어에 이미 extractor가 있으면 인라인으로 다시 파싱하지 말고 extractor를 확장하세요.

extractor가 한 파일로 감당하기 어려워지면 계속 키우지 말고 umbrella `require` 뒤에 파트 파일을 두는 디렉터리로 나누세요. [`go_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/go_route_extractor_ts)는 프레임워크 계열별로, [`kotlin_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/kotlin_route_extractor_ts)는 관심사별로 나뉘어 있습니다.

## 실행 모델 참고

`parallel_analyze`의 worker(그리고 그 위에 만든 `scan_files`, `parallel_file_scan`)는 Crystal 기본 execution context 위의 fiber입니다. 이 context는 스케줄러를 하나만 돌리지만, worker가 느린 syscall에 묶이면 런타임이 스케줄러를 다른 스레드로 넘길 수 있습니다. worker는 여전히 한 번에 하나씩 실행되지만, fiber가 다른 스레드에서 이어서 실행될 수 있고 끝나는 순서도 실행할 때마다 달라집니다. (`Noir::WorkerThreads`의 fiber는 다릅니다. 이 풀은 실제로 병렬로 돌기 때문에 공유 상태를 건드리지 않는 순수한 작업만 맡기세요.)

분석기를 쓸 때 지킬 점:

- 어떤 파일이 먼저 끝나느냐에 결과가 좌우되면 안 됩니다. 한 파일이 다른 파일을 덮어쓸 수 있는 병합(같은 컨트롤러 이름을 정의한 두 서비스 등)은 실행할 때마다 다른 쪽이 이깁니다.
- worker에서 공유 상태에 바로 추가하기보다 파일별 결과를 반환하세요. `FileScanEngine#analyze`는 이미 `analyze_file` 결과를 입력 순서대로 합칩니다. 커스텀 모양이라면 파일별 결과를 입력 순서대로 돌려주는 `ordered_file_scan`, `ordered_scan_files`, `ordered_parallel_analyze`를 쓰세요.
- `Noir::WorkerThreads`에서 실행될 수 있는 코드라면 공유하는 가변 컬렉션을 `Mutex`로 보호하세요.

오래된 분석기 중에는 아직 순회 안에서 공유 `result`에 바로 추가하는 것도 있습니다. 새 코드에 그대로 옮기지 마세요. 순서 의존 때문에 생긴 버그는 [#2770](https://github.com/owasp-noir/noir/pull/2770), [#2874](https://github.com/owasp-noir/noir/pull/2874)를 참고하세요.

## 다음에 볼 것

- 순회(L0) 참고: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- 얇은 어댑터(L2) 참고: [`javascript/hapi.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hapi.cr)
- 공용 파일 순회 베이스: [`engines/file_scan_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/file_scan_engine.cr)
- 엔진 + extractor 쌍: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor_ts.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor_ts.cr)
- 커스텀 모양 예시: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (전처리 단계 + 클로저 상태)
- 프레임워크 어댑터 예시: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (엔진 리팩터링 이후 처음 추가된 프레임워크)
