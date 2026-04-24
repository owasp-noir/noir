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
end
