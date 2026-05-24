require "../../spec_helper"
require "../../../src/models/deliver.cr"
require "../../../src/models/endpoint.cr"

describe "Initialize" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["probe_via"] = YAML::Any.new("http://localhost:8090")

  it "Deliver" do
    object = Deliver.new options
    object.proxy.should eq("http://localhost:8090")
  end

  it "Deliver with headers" do
    options["probe_header"] = YAML::Any.new([YAML::Any.new("X-API-Key: abcdssss")])
    object = Deliver.new options
    object.headers["X-API-Key"].should eq("abcdssss")
  end

  it "Deliver with headers (bearer case)" do
    options["probe_header"] = YAML::Any.new([YAML::Any.new("Authorization: Bearer gAAAAABl3qwaQqol243Np")])
    object = Deliver.new options
    object.headers["Authorization"].should eq("Bearer gAAAAABl3qwaQqol243Np")
  end

  it "Deliver with matchers" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.matchers[0].to_s.should eq("/admin")
  end

  it "Deliver with filters" do
    options["probe_skip"] = YAML::Any.new([YAML::Any.new("/admin")])
    object = Deliver.new options
    object.filters[0].to_s.should eq("/admin")
  end
end

describe "Method-based filtering" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["probe_via"] = YAML::Any.new("http://localhost:8090")

  # Create test endpoints
  endpoint1 = Endpoint.new("/api/users", "GET")
  endpoint2 = Endpoint.new("/api/users", "POST")
  endpoint3 = Endpoint.new("/admin/dashboard", "GET")
  endpoint4 = Endpoint.new("/login", "POST")
  endpoint5 = Endpoint.new("/upload", "PUT")
  test_endpoints = [endpoint1, endpoint2, endpoint3, endpoint4, endpoint5]

  it "applies matchers with URL-only pattern (backward compatibility)" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("/api")])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result[0].url.should eq("/api/users")
    result[0].method.should eq("GET")
    result[1].url.should eq("/api/users")
    result[1].method.should eq("POST")
  end

  it "applies matchers with method-only pattern" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("GET")])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result[0].method.should eq("GET")
    result[0].url.should eq("/api/users")
    result[1].method.should eq("GET")
    result[1].url.should eq("/admin/dashboard")
  end

  it "applies matchers with method:url pattern" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("POST:/api")])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(1)
    result[0].method.should eq("POST")
    result[0].url.should eq("/api/users")
  end

  it "applies filters with URL-only pattern (backward compatibility)" do
    options["probe_match"] = YAML::Any.new([] of YAML::Any)
    options["probe_skip"] = YAML::Any.new([YAML::Any.new("/admin")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(4)
    result.none?(&.url.includes?("/admin")).should be_true
  end

  it "applies filters with method-only pattern" do
    options["probe_match"] = YAML::Any.new([] of YAML::Any)
    options["probe_skip"] = YAML::Any.new([YAML::Any.new("POST")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(3)
    result.none? { |ep| ep.method == "POST" }.should be_true
  end

  it "applies filters with method:url pattern" do
    options["probe_match"] = YAML::Any.new([] of YAML::Any)
    options["probe_skip"] = YAML::Any.new([YAML::Any.new("GET:/api")])
    deliver = Deliver.new options

    result = deliver.apply_filters(test_endpoints)
    result.size.should eq(4)
    result.none? { |ep| ep.method == "GET" && ep.url.includes?("/api") }.should be_true
  end

  it "supports multiple matchers with different patterns" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("GET"), YAML::Any.new("POST:/login")])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
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
    options["probe_match"] = YAML::Any.new([YAML::Any.new("get")])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    result.size.should eq(2)
    result.all? { |ep| ep.method == "GET" }.should be_true
  end

  # Regression: previously the inner matcher loop did not break after
  # the first match, so an endpoint matched by several overlapping
  # patterns ended up emitted N times in the output.
  it "does not emit duplicates when an endpoint matches multiple matchers" do
    options["probe_match"] = YAML::Any.new([
      YAML::Any.new("GET"),      # matches GET /api/users, GET /admin/dashboard
      YAML::Any.new("GET:/api"), # also matches GET /api/users
    ])
    options["probe_skip"] = YAML::Any.new([] of YAML::Any)
    deliver = Deliver.new options

    result = deliver.apply_matchers(test_endpoints)
    # 2 distinct endpoints, not 3 (GET /api/users would have been
    # added twice under the old behavior).
    result.size.should eq(2)
    result.map(&.url).uniq!.size.should eq(2)
  end
end

describe "Deliver#apply_all chaining" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])

  endpoints = [
    Endpoint.new("/api/users", "GET"),
    Endpoint.new("/api/users", "POST"),
    Endpoint.new("/api/admin/users", "GET"),
    Endpoint.new("/admin/dashboard", "GET"),
    Endpoint.new("/login", "POST"),
  ]

  # Regression: apply_all used to call apply_filters(endpoints) on the
  # original list instead of the matcher-filtered result, so combining
  # matchers and filters silently dropped the matcher narrowing.
  it "feeds matcher output into filters (instead of the original list)" do
    options["probe_match"] = YAML::Any.new([YAML::Any.new("/api")])  # keep /api/*
    options["probe_skip"] = YAML::Any.new([YAML::Any.new("/admin")]) # drop /admin/*
    deliver = Deliver.new options

    result = deliver.apply_all(endpoints)

    # After the fix: matcher keeps GET /api/users, POST /api/users,
    # GET /api/admin/users; filter then drops GET /api/admin/users
    # because its URL contains "/admin".
    result.size.should eq(2)
    result.all?(&.url.starts_with?("/api/")).should be_true
    result.any?(&.url.includes?("/admin")).should be_false
  end
end

describe "Deliver#initialize header parsing" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])

  # Regression: split on every colon dropped everything after the
  # second one for values that legitimately contain `:`.
  it "preserves colons inside the header value" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new("Authorization: Bearer aaa:bbb:ccc"),
    ])
    deliver = Deliver.new options
    deliver.headers["Authorization"].should eq("Bearer aaa:bbb:ccc")
  end

  it "preserves multiple-colon header values like timestamps" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new("X-Request-Time: 12:34:56"),
    ])
    deliver = Deliver.new options
    deliver.headers["X-Request-Time"].should eq("12:34:56")
  end

  it "trims leading whitespace after the colon" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new("X-Foo:   value-with-spaces"),
    ])
    deliver = Deliver.new options
    deliver.headers["X-Foo"].should eq("value-with-spaces")
  end

  it "keeps the value as-is when no space follows the colon" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new("X-Bar:tight-value"),
    ])
    deliver = Deliver.new options
    deliver.headers["X-Bar"].should eq("tight-value")
  end

  # Bad-input handling: pre-fix, a malformed --probe-header was
  # silently dropped — `--probe-header "X-Auth tok123"` (missing
  # colon) led to the auth never reaching the receiver and the user
  # blaming the server. Now the entry is skipped *and* a stderr
  # warning is emitted. The spec covers the survival of the
  # well-formed entries; the warning text itself is covered by the
  # functional smoke during dogfooding.
  it "skips a header value with no colon (warning to stderr)" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new("X-Good: yes"),
      YAML::Any.new("X-No-Colon"),
    ])
    deliver = Deliver.new options
    deliver.headers["X-Good"].should eq("yes")
    deliver.headers.has_key?("X-No-Colon").should be_false
  end

  it "skips a header value with an empty name (warning to stderr)" do
    options["probe_header"] = YAML::Any.new([
      YAML::Any.new(":just-a-value"),
      YAML::Any.new("X-Real: 1"),
    ])
    deliver = Deliver.new options
    deliver.headers["X-Real"].should eq("1")
    deliver.headers.has_key?("").should be_false
  end
end
