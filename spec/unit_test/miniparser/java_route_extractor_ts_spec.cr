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
      # @RequestMapping without method defaults to GET for our purposes.
      {"GET", "/default"},
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
    ]
    missing = expected.reject { |e| found.includes?(e) }
    missing.should be_empty
  end
end
