require "../../spec_helper"
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

    urls = endpoints.map(&.url).sort
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

    urls = endpoints.map(&.url).sort
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

    urls = endpoints.map(&.url).sort
    urls.should contain("/health")
    urls.should contain("/api/users/")

    # Cleanup
    File.delete(temp_file)
    Dir.delete(temp_dir)
  end
end
