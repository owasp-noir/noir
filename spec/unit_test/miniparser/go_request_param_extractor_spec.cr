require "../../spec_helper"
require "../../../src/miniparsers/go_request_param_extractor"

describe Noir::GoRequestParamExtractor do
  describe "#params_for_routes" do
    it "extracts query and header parameters from go handler" do
      source = <<-GO
        package main
        import "net/http"

        func main() {
            http.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
                q := r.URL.Query().Get("search")
                h := r.Header.Get("X-API-Key")
            })
        }
        GO

      routes = Noir::TreeSitterGoRouteExtractor.extract_net_http_routes(source)
      params_map = Noir::GoRequestParamExtractor.params_for_routes(
        source,
        routes,
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new
      )

      params_map.has_key?({routes.first.offset, "GET", routes.first.path}).should be_true
      params = params_map[{routes.first.offset, "GET", routes.first.path}]
      params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
      params.any? { |p| p.name == "X-API-Key" && p.param_type == "header" }.should be_true
    end

    it "keeps recursive helper reads when reusing named handler results" do
      source = <<-GO
        package app
        func routes(r chi.Router) {
          r.Get("/first", first)
          r.Get("/second", second)
        }
        func first(w http.ResponseWriter, r *http.Request) { loop(r) }
        func second(w http.ResponseWriter, r *http.Request) { other(r) }
        func loop(r *http.Request) { r.Header.Get("X-Loop"); shared(r) }
        func other(r *http.Request) { shared(r) }
        func shared(r *http.Request) { loop(r) }
        GO
      files = {"/app/routes.go" => source}
      bodies = Noir::GoCalleeExtractor::LazyPackageBodies.new(files)
      resolver = Noir::GoRequestParamExtractor::Resolver.new(bodies, files, {} of String => String)
      functions = bodies.functions_for("/app")
      routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
      completed = Noir::GoRequestParamExtractor::BodyParams.new
      Noir::GoRequestParamExtractor.params_for_routes(source, routes, functions, bodies.methods_for("/app"),
        resolver: resolver, path: "/app/routes.go", body_params: completed)

      # In first -> loop -> shared, the recursion guard stops shared -> loop.
      # In second -> other -> shared, loop is reachable and reads X-Loop.
      completed.has_key?({functions["first"], "GET", nil}).should be_true
      {"first", "second"}.each do |name|
        params = Noir::GoRequestParamExtractor.params_for_body(functions[name], "GET", resolver, body_params: completed)
        params.map { |param| {param.name, param.param_type} }.should eq([{"X-Loop", "header"}])
      end
    end
  end

  describe "#lazy_package_bodies_for_dirs" do
    it "builds tables only for the requested directories" do
      contents = {
        "/app/a.go"     => "package app\n\nfunc Shared() int { return 1 }\nfunc (s *S) Get() {}\n",
        "/app/b.go"     => "package app\n\nfunc Shared() int { return 2 }\nfunc Only() {}\nfunc (t *T) Get() {}\n",
        "/app/tab.go"   => "package app\n\nfunc\tTabbed() {}\n",
        "/app/sub/c.go" => "package sub\n\nfunc Sub() {}\n",
        "/other/d.go"   => "package other\n\nfunc Other() {}\n",
      }
      dirs = Set{"/app", "/app/sub"}

      lazy = Noir::GoRequestParamExtractor.lazy_package_bodies_for_dirs(contents, dirs)

      # `func ` gate: the tab-separated declaration is skipped.
      Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, "/app").keys.sort!.should eq(["Only", "Shared"])
      Noir::GoRequestParamExtractor.method_bodies_for_directory(lazy, "/app").keys.should eq(["Get"])
      Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, "/app/sub").keys.should eq(["Sub"])
      # Directories outside `dirs` answer empty without parsing.
      ["/other", "/missing"].each do |dir|
        Noir::GoRequestParamExtractor.function_bodies_for_directory(lazy, dir).should be_empty
        Noir::GoRequestParamExtractor.method_bodies_for_directory(lazy, dir).should be_empty
      end
      # First definition wins, methods on different receivers accumulate.
      lazy.functions_for("/app")["Shared"].file_path.should eq("/app/a.go")
      lazy.methods_for("/app")["Get"].size.should eq(2)
    end
  end
end

describe Noir::GoRequestParamExtractor::Resolver do
  it "shares binding reachability across adapters and clears it between scans" do
    source = <<-GO
      package app
      func first(c *gin.Context, dst any) { second(c, dst) }
      func second(c *gin.Context, dst any) { first(c, dst); c.ShouldBindJSON(dst) }
      func unrelated(c *gin.Context) { c.Status(204) }
      GO
    files = {"routes.go" => source}
    bodies = Noir::GoCalleeExtractor::LazyPackageBodies.new(files)
    gin = Noir::GoRequestParamExtractor::Resolver.new(bodies, files, {} of String => String, "gin")
    echo = Noir::GoRequestParamExtractor::Resolver.new(bodies, files.dup, {} of String => String, "echo")
    helpers = gin.binding_helpers.not_nil!
    helpers.should eq(Set{"first", "second"})
    echo.binding_helpers.not_nil!.should be(helpers)

    Noir::ExtractionResultCache.clear_all
    Noir::GoRequestParamExtractor.binding_helpers(files).not_nil!.should_not be(helpers)
    changed = {"routes.go" => source.gsub("c.ShouldBindJSON(dst)", "c.Status(200)")}
    Noir::GoRequestParamExtractor.binding_helpers(changed).should eq(Set(String).new)
  end
end

describe Noir::GoRequestParamExtractor do
  it "applies a shared binding helper to each caller's destination" do
    source = <<-GO
      package app
      type A struct { First string `json:"first"` }
      type B struct { Second string `json:"second"` }
      func read(c *gin.Context, dst any) error { return c.ShouldBindJSON(dst) }
      GO
    files = {"handlers.go" => source}
    bodies = Noir::GoCalleeExtractor::LazyPackageBodies.new(files)
    resolver = Noir::GoRequestParamExtractor::Resolver.new(bodies, files, {} of String => String, "gin")
    {"A" => "first", "B" => "second", "Unknown" => "body"}.each do |type, expected|
      lines = ["func handle(c *gin.Context) {", "var request #{type}", "read(c, &request)", "}"]
      params = Noir::GoRequestParamExtractor.binding_params(lines, "handlers.go", "POST", resolver)
      params.map { |p| {p.name, p.param_type} }.should eq([{expected, "json"}])
      params.first.tags.map(&.name).should eq(type == "Unknown" ? ["unresolved"] : [] of String)
    end
  end
end

describe "Go binding tree lifetime" do
  it "borrows exact declarations and releases the file tree when the worker raises" do
    handler = "func handle() { read() }"
    source = "package app\n#{handler}"
    files = {"app.go" => source}
    bodies = Noir::GoCalleeExtractor::LazyPackageBodies.new(files)
    resolver = Noir::GoRequestParamExtractor::Resolver.new(bodies, files, {} of String => String, "gin")

    expect_raises(Exception, "worker failed") do
      Noir::TreeSitter.with_go_tree(source) do
        Noir::TreeSitter.parse_go(source) do |root|
          resolver.with_binding_tree(handler, "app.go") do |node, text|
            node.tree.should eq(root.tree)
            Noir::TreeSitter.node_text(node, text).should eq(handler)
          end
          resolver.with_binding_tree(handler.gsub("read", "other"), "app.go") do |node, _|
            node.tree.should_not eq(root.tree)
          end
        end
        raise "worker failed"
      end
    end
    Fiber.current.noir_go_tree.should be_nil
  end
end
