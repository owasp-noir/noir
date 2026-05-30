require "spec"
require "../../../src/miniparsers/java_route_extractor_ts"

describe Noir::TreeSitterJavaRouteExtractor do
  it "composes class-level and method-level @RequestMapping prefixes" do
    source = <<-JAVA
      package com.example;

      @RestController
      @RequestMapping("/api")
      public class UserController {
          @GetMapping("/users")
          public String list() { return ""; }

          @PostMapping("/users")
          public String create() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/api/users", "list"},
      {"POST", "/api/users", "create"},
    ])
  end

  it "handles value = / path = keyword arguments" do
    source = <<-JAVA
      public class K {
          @GetMapping(value = "/x")
          public String a() { return ""; }

          @PostMapping(path = "/y", produces = "application/json")
          public String b() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/x"},
      {"POST", "/y"},
    ])
  end

  it "derives the verb from RequestMethod for generic @RequestMapping" do
    source = <<-JAVA
      public class M {
          @RequestMapping(value = "/get", method = RequestMethod.GET)
          public String a() { return ""; }

          @RequestMapping(value = "/post", method = RequestMethod.POST)
          public String b() { return ""; }

          @RequestMapping("/default")
          public String c() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/get"},
      {"POST", "/post"},
      # Spring @RequestMapping without a method condition matches all methods.
      {"ANY", "/default"},
    ])
  end

  it "normalises the separator when the class prefix has no leading slash" do
    # Common Spring idiom: `@RequestMapping("items")` at class level and
    # `@GetMapping("{id}")` at method level — neither has a leading `/`
    # but the resolved path should be `/items/{id}`.
    source = <<-JAVA
      @RequestMapping("items")
      public class C {
          @GetMapping("{id}")
          public String get() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["items/{id}"])
  end

  it "handles multi-line annotations and trailing comments" do
    # Shape matches fixtures/java/spring/src/ItemController2.java. The
    # legacy lexer-based parser handles these with its own whitespace
    # eater; tree-sitter gets it for free.
    source = <<-JAVA
      @RestController
      @RequestMapping("items2")
      public class ItemController {
          @PostMapping(
              "/create" /* comment */
          )
          public String createItem() { return ""; }

          @PutMapping
          (
              "edit/"
          ) /* comment */
          public String editItem() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "items2/create"},
      {"PUT", "items2/edit/"},
    ])
  end

  it "recognises fully-qualified annotation names" do
    source = <<-JAVA
      public class F {
          @org.springframework.web.bind.annotation.GetMapping("/fq")
          public String a() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/fq"])
  end

  it "ignores methods with non-mapping annotations" do
    source = <<-JAVA
      public class X {
          @Override
          public String toString() { return ""; }

          @Deprecated
          public void legacy() {}
      }
      JAVA

    Noir::TreeSitterJavaRouteExtractor.extract_routes(source).should be_empty
  end

  it "fans out path arrays on @RequestMapping" do
    # `@RequestMapping({"/a", "/b"})` and the keyword form both emit
    # one endpoint per path literal.
    source = <<-JAVA
      public class A {
          @GetMapping({"/a", "/b"})
          public void x() {}

          @RequestMapping(value = {"/c", "/d"}, method = RequestMethod.POST)
          public void y() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/a"},
      {"GET", "/b"},
      {"POST", "/c"},
      {"POST", "/d"},
    ])
  end

  it "preserves empty path literals in mapping arrays" do
    source = <<-JAVA
      @RequestMapping({"", "/api"})
      public class A {
          @GetMapping({"", "/health"})
          public void x() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    # A bare method path on `/api` collapses to `/api` (no trailing
    # slash) — Spring absorbs the empty segment into the class prefix.
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", ""},
      {"GET", "/api"},
      {"GET", "/health"},
      {"GET", "/api/health"},
    ])
  end

  it "fans out class-level path arrays across method mappings" do
    source = <<-JAVA
      @RequestMapping({"/api", "/internal"})
      public class A {
          @GetMapping("/users")
          public void x() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users"},
      {"GET", "/internal/users"},
    ])
  end

  it "resolves compile-time String constants and concatenated paths" do
    source = <<-JAVA
      package com.example;

      public final class ApiPaths {
          public static final String API = "/api";
          public static final String USERS = API + "/users";
          public static final String DETAIL = USERS + "/{id}";
      }

      @RestController
      public class UsersController {
          private static final String LOCAL = "/local";
          private static final String DETAIL = LOCAL + "/{id}";

          @GetMapping(ApiPaths.DETAIL)
          public void show() {}

          @PostMapping(path = DETAIL)
          public void local() {}
      }
      JAVA

    constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants(source)
    constants["ApiPaths.DETAIL"].should eq("/api/users/{id}")
    constants["UsersController.DETAIL"].should eq("/local/{id}")

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/api/users/{id}", "show"},
      {"POST", "/local/{id}", "local"},
    ])
  end

  it "does not resolve unknown qualified constants by short name" do
    source = <<-JAVA
      public class UsersController {
          private static final String PATH = "/local";

          @GetMapping(External.PATH)
          public void external() {}

          @GetMapping(PATH)
          public void local() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/local", "local"},
    ])
  end

  it "fans out method arrays in @RequestMapping" do
    # Matches fixtures/java/spring/src/ItemController.java: both the
    # single-method and array-method forms.
    source = <<-JAVA
      @RequestMapping("items")
      public class C {
          @RequestMapping("/requestmap/put", method = RequestMethod.PUT)
          public void a() {}

          @RequestMapping("/requestmap/delete", method = {RequestMethod.DELETE})
          public void b() {}

          @RequestMapping("/multiple/methods", method = {RequestMethod.GET, RequestMethod.POST})
          public void c() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"PUT", "items/requestmap/put"},
      {"DELETE", "items/requestmap/delete"},
      {"GET", "items/multiple/methods"},
      {"POST", "items/multiple/methods"},
    ])
  end

  it "applies class-level RequestMapping verbs to generic method mappings" do
    source = <<-JAVA
      @RequestMapping(value = "/legacy", method = {RequestMethod.POST, RequestMethod.PUT})
      public class LegacyController {
          @RequestMapping("/submit")
          public void submit() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/legacy/submit"},
      {"PUT", "/legacy/submit"},
    ])
  end

  it "extracts Spring mapping params and headers conditions as endpoint params" do
    source = <<-JAVA
      @RequestMapping(value = "/tenant", params = "tenant")
      public class TenantController {
          @GetMapping(value = "/reports", params = {"mode=full", "!skip"}, headers = {"X-Client=mobile", "!X-Debug"})
          public void reports() {}
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"GET", "/tenant/reports", [
        Param.new("tenant", "", "query"),
        Param.new("mode", "full", "query"),
        Param.new("X-Client", "mobile", "header"),
      ]},
    ])
  end

  it "extracts same-file Spring composed mapping annotations" do
    source = <<-JAVA
      package com.example;

      import org.springframework.web.bind.annotation.*;

      @RequestMapping("/internal")
      public @interface InternalApi {}

      @GetMapping("/reports")
      public @interface ReportsGet {}

      @RequestMapping(method = RequestMethod.POST)
      public @interface JsonPost {
          String value() default "";
      }

      @RestController
      @InternalApi
      public class ReportsController {
          @ReportsGet
          public String list() { return ""; }

          @JsonPost("/submit")
          public String submit() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/internal/reports", "list"},
      {"POST", "/internal/submit", "submit"},
    ])
  end

  it "applies externally supplied Spring composed mapping annotations" do
    annotation_source = <<-JAVA
      package com.example.annotations;

      import org.springframework.web.bind.annotation.*;

      @RequestMapping("/external")
      public @interface ExternalApi {}

      @DeleteMapping
      public @interface ExternalDelete {
          String value() default "";
      }
      JAVA

    controller_source = <<-JAVA
      package com.example;

      import com.example.annotations.ExternalApi;
      import com.example.annotations.ExternalDelete;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      @ExternalApi
      public class ReportsController {
          @ExternalDelete("/reports/{id}")
          public void delete() {}
      }
      JAVA

    mappings = Hash(String, Noir::TreeSitterJavaRouteExtractor::ClassMapping).new
    Noir::TreeSitter.parse_java(annotation_source) do |root|
      mappings = Noir::TreeSitterJavaRouteExtractor.extract_meta_mappings_from(root, annotation_source)
    end

    routes = [] of Noir::TreeSitterJavaRouteExtractor::Route
    Noir::TreeSitter.parse_java(controller_source) do |root|
      routes = Noir::TreeSitterJavaRouteExtractor.extract_routes_from(root, controller_source, mappings)
    end

    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"DELETE", "/external/reports/{id}", "delete"},
    ])
  end

  it "extracts Spring Cloud Gateway Java route predicates" do
    source = <<-JAVA
      package com.example;

      public class GatewayRouteConfig {
          static final class GatewayPolicy {
              public static final String MCP_ENDPOINT_PATH = "/mcp";
          }

          RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
              return builder.routes()
                  .route("post", r -> r.method(HttpMethod.POST).and().path(GatewayPolicy.MCP_ENDPOINT_PATH).uri("no://op"))
                  .route("multi", r -> r.method(HttpMethod.GET, HttpMethod.DELETE).and().path("/multi", "/alt").uri("no://op"))
                  .route("any", r -> r.path("/public/**").uri("no://op"))
                  .route("helper", r -> isPutRequestToMcpEndpoint(r).uri("no://op"))
                  .build();
          }

          private BooleanSpec isPutRequestToMcpEndpoint(PredicateSpec predicateSpec) {
              return predicateSpec.method(HttpMethod.PUT).and().path(GatewayPolicy.MCP_ENDPOINT_PATH);
          }
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/mcp"},
      {"GET", "/multi"},
      {"GET", "/alt"},
      {"DELETE", "/multi"},
      {"DELETE", "/alt"},
      {"ANY", "/public/**"},
      {"PUT", "/mcp"},
    ])
  end

  it "keeps controller-interface mappings as definitions instead of standalone endpoints" do
    source = <<-JAVA
      package com.example;

      @RequestMapping("/catalog")
      public interface CatalogApi {
          @GetMapping("/{id}")
          Catalog getCatalog(@PathVariable("id") String id);
      }

      @RestController
      @RequestMapping("/api")
      public class CatalogController implements CatalogApi {}
      JAVA

    Noir::TreeSitterJavaRouteExtractor.extract_routes(source).should be_empty

    interface_routes = Hash(String, Array(Noir::TreeSitterJavaRouteExtractor::Route)).new
    implementations = [] of Noir::TreeSitterJavaRouteExtractor::ControllerInterfaceImplementation
    Noir::TreeSitter.parse_java(source) do |root|
      interface_routes = Noir::TreeSitterJavaRouteExtractor.extract_interface_routes_from(root, source)
      implementations = Noir::TreeSitterJavaRouteExtractor.extract_controller_interface_implementations_from(root, source)
    end

    interface_routes["CatalogApi"].map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/catalog/{id}", "getCatalog"},
    ])
    implementations.map { |i| {i.class_name, i.interface_names, i.paths} }.should eq([
      {"CatalogController", ["CatalogApi"], ["/api"]},
    ])
  end

  it "walks `interface_declaration` bodies for @FeignClient" do
    # Spring Cloud Feign interfaces are routes too; tree-sitter
    # emits `interface_declaration` for `public interface Foo { ... }`
    # rather than `class_declaration`.
    source = <<-JAVA
      @FeignClient(name = "inventory-service", url = "...")
      public interface InventoryClient {
          @PatchMapping("/api/v2/items/{id}/stock")
          void updateStock(@PathVariable Long id);

          @GetMapping("/api/v2/items")
          List<Item> list(@RequestParam String category);
      }
      JAVA

    routes = Noir::TreeSitterJavaRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"PATCH", "/api/v2/items/{id}/stock"},
      {"GET", "/api/v2/items"},
    ])
  end

  it "reaches parity with the annotation-based portion of the Spring functional fixture" do
    # Sanity sweep: run the extractor over every .java file in the
    # bundled Spring fixture and confirm every annotation-based
    # endpoint the functional tester expects shows up in the
    # extracted set. Reactive `router().route()` endpoints are out of
    # scope for this extractor and are excluded from the check.
    fixture_dir = File.expand_path("../../../functional_test/fixtures/java/spring/src", __FILE__)

    found = Set(Tuple(String, String)).new
    Dir.glob("#{fixture_dir}/*.java") do |path|
      content = File.read(path)
      Noir::TreeSitterJavaRouteExtractor.extract_routes(content).each do |r|
        found << {r.verb, r.path}
      end
    end

    # Every annotation-based endpoint in `spring_spec.cr` should be
    # present. Paths match the class prefix exactly as declared in
    # each fixture — e.g. ItemController.java uses
    # `@RequestMapping("/items")`, so its routes come out with a
    # leading slash.
    expected = [
      # ItemController.java — class @RequestMapping("/items")
      {"GET", "/items/{id}"},
      {"PUT", "/items/update/{id}"},
      {"DELETE", "/items/delete/{id}"},
      {"PUT", "/items/requestmap/put"},
      {"DELETE", "/items/requestmap/delete"},
      {"ANY", "/items/any-method"},
      {"GET", "/items/multiple/methods"},
      {"POST", "/items/multiple/methods"},
      # ItemController2.java — class @RequestMapping("items2")
      {"GET", "items2/{id}"},
      {"POST", "items2/create"},
      {"PUT", "items2/edit/"},
      {"GET", "items2/{id}/thePath"},
      # InventoryClient.java — @FeignClient interface, no class prefix
      {"PATCH", "/api/v2/items/{id}/stock"},
      {"GET", "/api/v2/items"},
      {"POST", "/api/v2/items"},
      {"DELETE", "/api/v2/items/{id}"},
      # ComposedAnnotationController.java — same-file meta annotations
      {"GET", "/internal/reports"},
      {"POST", "/internal/submit"},
    ]
    missing = expected.reject { |e| found.includes?(e) }
    missing.should be_empty
  end
end
