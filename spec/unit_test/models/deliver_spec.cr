require "spec"
require "../../../src/models/deliver.cr"
require "../../../src/models/endpoint.cr"
require "../../../src/options.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["send_proxy"] = YAML::Any.new("http://localhost:8090")
  options["nolog"] = YAML::Any.new(true)

  it "Deliver" do
    object = Deliver.new options
    object.proxy.should eq("http://localhost:8090")
  end

  it "Deliver with headers" do
    options["send_with_headers"] = YAML::Any.new([YAML::Any.new("X-API-Key: abcdssss")])
    object = Deliver.new options
    object.headers["X-API-Key"].should eq("abcdssss")
  end

  it "Deliver with headers (bearer case)" do
    options["send_with_headers"] = YAML::Any.new([YAML::Any.new("Authorization: Bearer gAAAAABl3qwaQqol243Np")])
    object = Deliver.new options
    object.headers["Authorization"].should eq("Bearer gAAAAABl3qwaQqol243Np")
  end

  it "Deliver with matchers" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.matchers[0].to_s.should eq("/admin")
  end

  it "Deliver with filters" do
    options["use_filters"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.filters[0].to_s.should eq("/admin")
  end
end

describe "Method-based filtering" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["send_proxy"] = YAML::Any.new("http://localhost:8090")
  options["nolog"] = YAML::Any.new(true)

  # Create test endpoints
  endpoint1 = Endpoint.new("/api/users", "GET")
  endpoint2 = Endpoint.new("/api/users", "POST")
  endpoint3 = Endpoint.new("/admin/dashboard", "GET")
  endpoint4 = Endpoint.new("/login", "POST")
  endpoint5 = Endpoint.new("/upload", "PUT")
  test_endpoints = [endpoint1, endpoint2, endpoint3, endpoint4, endpoint5]

  it "applies matchers with URL-only pattern (backward compatibility)" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("/api")])
    options["use_filters"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result[0].url.should eq("/api/users")
    result[0].method.should eq("GET")
    result[1].url.should eq("/api/users")
    result[1].method.should eq("POST")
  end

  it "applies matchers with method-only pattern" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("GET")])
    options["use_filters"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result[0].method.should eq("GET")
    result[0].url.should eq("/api/users")
    result[1].method.should eq("GET")
    result[1].url.should eq("/admin/dashboard")
  end

  it "applies matchers with method:url pattern" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("POST:/api")])
    options["use_filters"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(1)
    result[0].method.should eq("POST")
    result[0].url.should eq("/api/users")
  end

  it "applies filters with URL-only pattern (backward compatibility)" do
    options["use_matchers"] = YAML::Any.new([] of YAML::Any)
    options["use_filters"] = YAML::Any.new([YAML::Any.new("/admin")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(4)
    result.none?(&.url.includes?("/admin")).should be_true
  end

  it "applies filters with method-only pattern" do
    options["use_matchers"] = YAML::Any.new([] of YAML::Any)
    options["use_filters"] = YAML::Any.new([YAML::Any.new("POST")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(3)
    result.none? { |ep| ep.method == "POST" }.should be_true
  end

  it "applies filters with method:url pattern" do
    options["use_matchers"] = YAML::Any.new([] of YAML::Any)
    options["use_filters"] = YAML::Any.new([YAML::Any.new("GET:/api")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(4)
    result.none? { |ep| ep.method == "GET" && ep.url.includes?("/api") }.should be_true
  end

  it "supports multiple matchers with different patterns" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("GET"), YAML::Any.new("POST:/login")])
    options["use_filters"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(3)
    # Should include GET /api/users, GET /admin/dashboard, and POST /login
    get_endpoints = result.select { |ep| ep.method == "GET" }
    post_login_endpoints = result.select { |ep| ep.method == "POST" && ep.url.includes?("/login") }
    get_endpoints.size.should eq(2)
    post_login_endpoints.size.should eq(1)
  end

  it "case insensitive method matching" do
    options["use_matchers"] = YAML::Any.new([YAML::Any.new("get")])
    options["use_filters"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result.all? { |ep| ep.method == "GET" }.should be_true
  end
end
