require "spec"
require "../../../src/miniparsers/kotlin_route_extractor_ts"

describe Noir::TreeSitterKotlinRouteExtractor do
  it "composes class-level and method-level mapping prefixes" do
    source = <<-KT
      package com.example

      @RestController
      @RequestMapping("/api")
      class UserController {
          @GetMapping("/users")
          fun list(): String = ""

          @PostMapping("/users")
          fun create(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/api/users", "list"},
      {"POST", "/api/users", "create"},
    ])
  end

  it "handles value = / path = keyword arguments" do
    source = <<-KT
      class K {
          @GetMapping(value = "/x")
          fun a(): String = ""

          @PostMapping(path = "/y", produces = ["application/json"])
          fun b(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/x"},
      {"POST", "/y"},
    ])
  end

  it "derives the verb from RequestMethod for generic @RequestMapping" do
    source = <<-KT
      class M {
          @RequestMapping(value = "/get", method = [RequestMethod.GET])
          fun a(): String = ""

          @RequestMapping(value = "/post", method = [RequestMethod.POST])
          fun b(): String = ""

          @RequestMapping("/default")
          fun c(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/get"},
      {"POST", "/post"},
      {"GET", "/default"},
    ])
  end

  it "fans out method arrays in @RequestMapping" do
    source = <<-KT
      @RequestMapping("items")
      class C {
          @RequestMapping("/multiple/methods", method = [RequestMethod.GET, RequestMethod.POST])
          fun c(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "items/multiple/methods"},
      {"POST", "items/multiple/methods"},
    ])
  end

  it "fans out path arrays on mapping annotations" do
    source = <<-KT
      class A {
          @GetMapping(value = ["/a", "/b"])
          fun x(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/a"},
      {"GET", "/b"},
    ])
  end

  it "emits prefix/ when the method path is empty" do
    # Kotlin Spring controllers routinely do
    # `@RequestMapping("/api/article")` on the class and `@GetMapping`
    # (no path arg) on a method, expecting `/api/article/` for the
    # handler. Matches the Java Spring behaviour pinned down in #1291.
    source = <<-KT
      @RequestMapping("/api/article")
      class ArticleController {
          @GetMapping
          fun list(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/api/article/"])
  end

  it "ignores non-mapping annotations" do
    source = <<-KT
      class X {
          @Deprecated("old")
          fun legacy(): Unit = Unit
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_routes(source).should be_empty
  end
end
