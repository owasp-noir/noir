require "../../src/models/endpoint.cr"

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
end