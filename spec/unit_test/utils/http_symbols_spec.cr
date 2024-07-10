require "../../../src/utils/*"

describe "http_symbols test" do
  it "GET" do
    get_symbol("GET").should eq(:get)
  end

  it "POST" do
    get_symbol("POST").should eq(:post)
  end

  it "PUT" do
    get_symbol("PUT").should eq(:put)
  end

  it "DELETE" do
    get_symbol("DELETE").should eq(:delete)
  end

  it "PATCH" do
    get_symbol("PATCH").should eq(:patch)
  end

  it "OPTIONS" do
    get_symbol("OPTIONS").should eq(:options)
  end

  it "HEAD" do
    get_symbol("HEAD").should eq(:head)
  end

  it "TRACE" do
    get_symbol("TRACE").should eq(:trace)
  end

  it "CONNECT" do
    get_symbol("CONNECT").should eq(:connect)
  end
end
