require "../../func_spec.cr"
require "file_utils"

expected_endpoints = [
  Endpoint.new("/hello/:name", "GET", [Param.new("name", "", "path")]),
  # No path or method and no request struct: /<package>.<Func> on GET and POST.
  Endpoint.new("/hello.Ping", "GET"),
  Endpoint.new("/hello.Ping", "POST"),
  # `raw` without a method accepts any method.
  Endpoint.new("/webhooks/*rest", "ANY", [Param.new("rest", "", "path")]),
  # The `!fallback` route is reported as a `*fallback` wildcard.
  Endpoint.new("/*fallback", "GET", [Param.new("fallback", "", "path")]),
  # Request struct in another file of the package; GET sends untagged fields as snake_case query.
  Endpoint.new("/users", "GET", [
    Param.new("limit", "", "query"),
    Param.new("cursor", "", "query"),
    Param.new("X-Tenant", "", "header"),
    # `json:"-"` drops only a JSON-body field.
    Param.new("Authorization", "", "header"),
    Param.new("offset", "", "query"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  Endpoint.new("/users/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  # A request payload and no method defaults to POST.
  Endpoint.new("/users.Create", "POST", [
    Param.new("display_name", "", "json"),
    Param.new("Email", "", "json"),
    Param.new("X-Request-ID", "", "header"),
  ]),
  # `*shared.Other` is not the package's own `Other` struct.
  Endpoint.new("/users/import", "POST"),
]

FunctionalTester.new("fixtures/go/encore/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Encore Go access tags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags access and auth from the directive" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/encore/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map { |tag| {tag.name, tag.description} }
    end

    tags.call("GET", "/hello/:name").should eq [{"encore-access", "public"}]
    tags.call("GET", "/users").should contain({"auth", "Encore auth endpoint"})
    tags.call("POST", "/users.Create").should eq [{"encore-access", "private"}]
  end
end

describe "Encore Go access requirements", tags: "functional" do
  scan = ->(dir : String) do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end
  reading = ->(endpoints : Array(Endpoint), method : String, url : String) do
    Access.of(endpoints.find! { |ep| ep.method == method && ep.url == url }).map(&.to_s)
  end

  it "reads public as open, auth as signed in, private as unread" do
    endpoints = scan.call("./spec/functional_test/fixtures/go/encore/")
    reading.call(endpoints, "GET", "/hello/:name").should eq ["anonymous"]
    reading.call(endpoints, "GET", "/users").should eq ["anonymous", "authenticated"]
    reading.call(endpoints, "POST", "/users.Create").should eq ["unresolved"]
    endpoints.find! { |ep| ep.url == "/users.Create" }.tags.first.requires.not_nil!.first.any_of.first.value.should eq "private"
  end

  it "keeps a middleware that targets the endpoint unread" do
    dir = File.tempname("encore_mw")
    Dir.mkdir_p(File.join(dir, "svc"))
    File.write(File.join(dir, "encore.app"), %({"id": "x"}))
    File.write(File.join(dir, "go.mod"), "module encore.app\n\nrequire encore.dev v1.41.0\n")
    File.write(File.join(dir, "svc", "svc.go"), <<-GO)
      package svc

      import (
      	"context"

      	"encore.dev/middleware"
      )

      //encore:middleware target=tag:gated
      func Gate(req middleware.Request, next middleware.Next) middleware.Response {
      	return next(req)
      }

      //encore:api public method=GET path=/open
      func Open(ctx context.Context) error { return nil }

      //encore:api public tag:gated method=GET path=/gated
      func Gated(ctx context.Context) error { return nil }

      //encore:api auth tag:gated method=GET path=/me
      func Me(ctx context.Context) error { return nil }
      GO
    Dir.mkdir_p(File.join(dir, "other"))
    File.write(File.join(dir, "other", "other.go"), <<-GO)
      package other

      import "context"

      //encore:api public tag:gated method=GET path=/other
      func Other(ctx context.Context) error { return nil }
      GO
    begin
      endpoints = scan.call(dir)
      reading.call(endpoints, "GET", "/open").should eq ["anonymous"]
      reading.call(endpoints, "GET", "/gated").should eq ["anonymous", "unresolved"]
      reading.call(endpoints, "GET", "/me").should eq ["anonymous", "unresolved", "authenticated"]
      # Not `global`: another service's endpoints run without it.
      reading.call(endpoints, "GET", "/other").should eq ["anonymous"]
      clauses = Access.of(endpoints.find! { |ep| ep.url == "/gated" })
      Access.cell(clauses, Access::Atom.new(:anonymous)).should be_nil
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
