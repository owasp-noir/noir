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
end
