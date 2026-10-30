require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/crystal/kemal.cr"

describe "mapping_to_path" do
  options = create_test_options
  instance = Analyzer::Crystal::Kemal.new(options)

  it "line_to_param - env.params.query" do
    line = "env.params.query[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.params.json" do
    line = "env.params.json[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.params.body" do
    line = "env.params.body[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.response.headers[]" do
    line = "env.request.headers[\"x-token\"]"
    instance.line_to_param(line).name.should eq("x-token")
  end
end

describe "kemal namespace routing" do
  options = create_test_options
  instance = Analyzer::Crystal::Kemal.new(options)

  it "parses namespace with mount prefix" do
    # Create a temp file with namespace routing
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      api = Kemal::Router.new
      api.namespace "/users" do
        get "/" do |env|
          "user list"
        end
        get "/:id" do |env|
          "user detail"
        end
      end
      mount "/api/v1", api
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)

    urls = endpoints.map(&.url).sort!
    urls.should contain("/api/v1/users/")
    urls.should contain("/api/v1/users/:id")

    methods = endpoints.map(&.method)
    methods.all? { |m| m == "GET" }.should be_true

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "parses namespace without mount (bare namespace)" do
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      namespace "/admin" do
        get "/dashboard" do |env|
          "dashboard"
        end
        post "/settings" do |env|
          "settings"
        end
      end
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)

    urls = endpoints.map(&.url).sort!
    urls.should contain("/admin/dashboard")
    urls.should contain("/admin/settings")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "parses nested namespaces" do
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      namespace "/api" do
        namespace "/v2" do
          get "/items" do |env|
            "items"
          end
        end
      end
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/api/v2/items")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "parses params inside namespace" do
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      api = Kemal::Router.new
      api.namespace "/users" do
        get "/" do |env|
          env.params.query["page"]
          "user list"
        end
      end
      mount "/api/v1", api
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/api/v1/users/")
    endpoints[0].params.size.should eq(1)
    endpoints[0].params[0].name.should eq("page")
    endpoints[0].params[0].param_type.should eq("query")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "parses HTTP QUERY routes and excludes before_query/after_query filters" do
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      query "/search" do |env|
        env.params.json["q"]?
        env.params.query["mode"]
        "search results"
      end

      before_query "/admin/*" do |env|
        env.response.status_code = 403
      end

      after_query "/admin/*" do |env|
        env.response.headers["x-filtered"] = "true"
      end
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/search")
    endpoints[0].method.should eq("QUERY")

    params = endpoints[0].params
    params.size.should eq(2)
    params.find { |p| p.name == "q" }.try(&.param_type).should eq("json")
    params.find { |p| p.name == "mode" }.try(&.param_type).should eq("query")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "handles routes outside namespace normally" do
    temp_dir = File.tempname("kemal_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      get "/health" do |env|
        "ok"
      end

      api = Kemal::Router.new
      api.namespace "/users" do
        get "/" do |env|
          "users"
        end
      end
      mount "/api", api
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)

    urls = endpoints.map(&.url).sort!
    urls.should contain("/health")
    urls.should contain("/api/users/")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end
end

describe "kemal cross-file mounts" do
  it "prefixes a router mounted from another file" do
    temp_dir = File.tempname("kemal_mount")
    files = {
      "src/app.cr" => <<-CRYSTAL,
        require "kemal"
        require "./routes/users"
        mount "/api", USERS_ROUTER
        Kemal.run
        CRYSTAL
      "src/routes/users.cr" => <<-CRYSTAL,
        USERS_ROUTER = Kemal::Router.new
        USERS_ROUTER.namespace "/users" do
          get "/:id" do |env|
            env.params.url["id"]
          end
        end
        CRYSTAL
    }
    CodeLocator.instance.clear_all
    files.each do |relative, content|
      path = File.join(temp_dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      CodeLocator.instance.register_file(path, content)
    end
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])

    Analyzer::Crystal::Kemal.new(options).analyze.map(&.url).should eq(["/api/users/:id"])
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "ignores spec-kemal client calls outside spec/ and keeps a handler on the next line" do
    temp_dir = File.tempname("kemal_spec_client")
    script = File.join(temp_dir, "scripts", "smoke.cr")
    content = <<-CRYSTAL
      require "spec-kemal"
      require "../src/app"

      r = get("/items/7")
      puts delete("/items/7").status_code
      puts get("/search?tags[]=a&tags[]=b").body
      post("/items",
        headers: HTTP::Headers{"A" => "b"})

      get "/k/multiline",
        do |env|
        "x"
      end
      CRYSTAL
    CodeLocator.instance.clear_all
    Dir.mkdir_p(File.dirname(script))
    File.write(script, content)
    CodeLocator.instance.register_file(script, content)

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    analyzer = Analyzer::Crystal::Kemal.new(options)
    analyzer.analyze.map { |ep| "#{ep.method} #{ep.url}" }.should eq(["GET /k/multiline"])
    analyzer.line_to_endpoint(%(r = get("/items/7"))).method.should eq("")
    analyzer.line_to_endpoint(%(puts delete("/items/7").status_code)).method.should eq("")
    analyzer.line_to_endpoint(%(post "/users", headers: HTTP::Headers{"A" => "b"}, body: "x")).method.should eq("")
    {
      %(get "/items/:id" do |env|),
      %(get("/items/:id") { |env| env }),
      %(get "/items/:id", &handler),
      %(get "/items/:id", Routes::Items, :show),
      %(get "/items/:id", {{ namespace }}::Items, :show),
    }.each do |line|
      analyzer.line_to_endpoint(line).url.should eq("/items/:id")
    end
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end

describe "kemal router-instance routes" do
  it "reads verbs called on a Kemal::Router variable, joined with its mount" do
    temp_dir = File.tempname("kemal_router_instance")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "app.cr")
    File.write(temp_file, <<-CRYSTAL)
      module App
        def self.run
          router = Kemal::Router.new
          client = HTTP::Client.new("example.com")

          router.get "/items" do |env|
            env.params.query["page"]?
          end

          router.post("/items/:id") do |env|
            env.params.url["id"]
          end

          router.ws "/live" do |socket|
          end

          # Not routes: an HTTP client call, a filter, an unknown receiver.
          client.get "/upstream"
          router.before_get "/items" do |env|
          end
          other.get "/elsewhere"

          mount "/api", router
          Kemal.run
        end
      end
      CRYSTAL

    endpoints = Analyzer::Crystal::Kemal.new(create_test_options).analyze_file(temp_file)
    endpoints.map { |ep| {ep.method, ep.url, ep.protocol} }.should eq([
      {"GET", "/api/items", "http"},
      {"POST", "/api/items/:id", "http"},
      {"GET", "/api/live", "ws"},
    ])
    endpoints[0].params.map(&.name).should eq(["page"])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "reads a Kemal::Router constant declared in another file, but not a local" do
    temp_dir = File.tempname("kemal_router_const")
    files = {
      "src/app.cr" => <<-CRYSTAL,
        require "kemal"
        API = Kemal::Router.new
        local = Kemal::Router.new
        mount "/v1", API
        Kemal.run
        CRYSTAL
      "src/routes/items.cr" => <<-CRYSTAL,
        API.get "/items" do |env|
        end
        local.get "/not-this-files-router" do |env|
        end
        CRYSTAL
    }
    CodeLocator.instance.clear_all
    files.each do |relative, content|
      path = File.join(temp_dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      CodeLocator.instance.register_file(path, content)
    end
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])

    Analyzer::Crystal::Kemal.new(options).analyze.map(&.url).should eq(["/v1/items"])
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "follows constructor prefixes, nested router mounts, typed declarations and sse" do
    temp_dir = File.tempname("kemal_router_api")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "app.cr")
    File.write(temp_file, <<-CRYSTAL)
      prefixed = Kemal::Router.new("/pre")
      prefixed.get "/a" do |env|
      end

      users = Kemal::Router.new
      users.get "/list" do |env|
      end
      api = Kemal::Router.new
      api.mount "/users", users
      mount "/api", api

      typed : Kemal::Router = Kemal::Router.new
      typed.get "/typed" do |env|
      end

      events = Kemal::Router.new
      events.sse "/events" do |stream, env|
      end

      cache.get "k"; api.get "/second-on-line" do |env|
      end
      CRYSTAL

    endpoints = Analyzer::Crystal::Kemal.new(create_test_options).analyze_file(temp_file)
    endpoints.map { |ep| {ep.method, ep.url} }.should eq([
      {"GET", "/pre/a"},
      {"GET", "/api/users/list"},
      {"GET", "/typed"},
      {"GET", "/events"},
      {"GET", "/api/second-on-line"},
    ])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "drops a mount cycle and serves a twice-mounted router under both paths" do
    temp_dir = File.tempname("kemal_router_mounts")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "app.cr")
    File.write(temp_file, <<-CRYSTAL)
      ca = Kemal::Router.new
      cb = Kemal::Router.new
      ca.mount "/x", cb
      cb.mount "/y", ca
      ca.get "/cyc" do |env|
      end

      twice = Kemal::Router.new
      twice.get "/t" do |env|
        env.params.query["q"]
      end
      mount "/one", twice
      mount "/two", twice
      CRYSTAL

    endpoints = Analyzer::Crystal::Kemal.new(create_test_options).analyze_file(temp_file)
    endpoints.map(&.url).should eq(["/cyc", "/one/t", "/two/t"])
    endpoints[1].params.map(&.name).should eq(["q"])
    endpoints[2].params.map(&.name).should eq(["q"])
    endpoints[2].details.code_paths[0].line.should eq(9)
    # Each copy owns its params, so tagging or merging one leaves the other alone.
    endpoints[1].params.same?(endpoints[2].params).should be_false
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "binds `||=` routers and keeps a binding across `||=` and def parameter defaults" do
    temp_dir = File.tempname("kemal_router_memo")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "app.cr")
    File.write(temp_file, <<-CRYSTAL)
      class App
        def build
          @r ||= Kemal::Router.new
          @r.get "/memo" do |env|
          end
          @@shared ||= Kemal::Router.new
          @@shared.get "/class-var" do |env|
          end
        end
      end

      cmp = Kemal::Router.new
      cmp ||= other
      def helper(cmp = nil)
      end
      cmp.get "/kept" do |env|
      end
      CRYSTAL

    Analyzer::Crystal::Kemal.new(create_test_options).analyze_file(temp_file).map(&.url).should eq([
      "/memo", "/class-var", "/kept",
    ])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "unbinds a router name reassigned to something else" do
    temp_dir = File.tempname("kemal_router_reassign")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "app.cr")
    File.write(temp_file, <<-CRYSTAL)
      def a
        router = Kemal::Router.new
        router.get "/real" do |env|
        end
        mount router
      end

      def b
        router = HTTP::Client.new("h")
        router.get "/upstream"
      end
      CRYSTAL

    Analyzer::Crystal::Kemal.new(create_test_options).analyze_file(temp_file).map(&.url).should eq(["/real"])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "keeps two Kemal projects under one scan base apart" do
    temp_dir = File.tempname("kemal_router_mono")
    shard = <<-YAML
      name: app
      dependencies:
        kemal:
          github: kemalcr/kemal
      YAML
    files = {} of String => String
    {"a", "b"}.each do |name|
      files["#{name}/shard.yml"] = shard
      files["#{name}/src/app.cr"] = "API = Kemal::Router.new\nmount \"/#{name}\", API\n"
      files["#{name}/src/routes.cr"] = "API.get \"/from-#{name}\" do |env|\nend\nAPI.namespace \"/n\" do\n  get \"/ns-#{name}\" do |env|\n  end\nend\n"
    end
    CodeLocator.instance.clear_all
    files.each do |relative, content|
      path = File.join(temp_dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      CodeLocator.instance.register_file(path, content)
    end
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])

    Analyzer::Crystal::Kemal.new(options).analyze.map(&.url).sort!.should eq([
      "/a/from-a", "/a/n/ns-a", "/b/from-b", "/b/n/ns-b",
    ])
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
