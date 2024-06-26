require "../../../src/models/endpoint.cr"

describe "Initialize 2 arguments" do
  endpoint = Endpoint.new("/abcd", "GET")
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([] of Param)
  end
end

describe "Initialize 3 arguments" do
  endpoint = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([Param.new("a", "b", "query")])
  end

  path = "path/a/b/c"
  line = 123
  path_info = PathInfo.new(path, line)
  endpoint2 = Endpoint.new("/abcd", "GET", Details.new(path_info))
  it "detect_url" do
    endpoint2.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint2.method.should eq("GET")
  end
  it "detect_details" do
    endpoint2.details.should eq(Details.new(path_info))
    endpoint2.details.code_paths[0].path.should eq(path)
    endpoint2.details.code_paths[0].line.should eq(line)
  end
end

describe "Initialize 4 arguments" do
  path = "path/a/b/c"
  line = 123
  path_info = PathInfo.new(path, line)
  endpoint = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")], Details.new(path_info))
  it "detect_url" do
    endpoint.url.should eq("/abcd")
  end
  it "detect_method" do
    endpoint.method.should eq("GET")
  end
  it "detect_params" do
    endpoint.params.should eq([Param.new("a", "b", "query")])
  end
  it "detect_details" do
    endpoint.details.should eq(Details.new(path_info))
    endpoint.details.code_paths[0].path.should eq(path)
    endpoint.details.code_paths[0].line.should eq(line)
  end
end

describe "Endpoint equality" do
  it "same endpoints" do
    endpoint1 = Endpoint.new("/abcd", "GET")
    endpoint2 = Endpoint.new("/abcd", "GET")
    (endpoint1 == endpoint2).should eq(true)
  end

  it "different endpoints" do
    endpoint1 = Endpoint.new("/abcd", "GET")
    endpoint2 = Endpoint.new("/abcd", "POST")
    (endpoint1 == endpoint2).should eq(false)
  end

  it "same endpoints with params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    (endpoint1 == endpoint2).should eq(true)
  end

  it "different endpoints with params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "json")])
    (endpoint1 == endpoint2).should eq(false)
  end

  it "same endpoints and suffled params" do
    endpoint1 = Endpoint.new("/abcd", "GET", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])
    endpoint2 = Endpoint.new("/abcd", "GET", [Param.new("c", "d", "json"), Param.new("a", "b", "query")])
    (endpoint1 == endpoint2).should eq(true)
  end
end
