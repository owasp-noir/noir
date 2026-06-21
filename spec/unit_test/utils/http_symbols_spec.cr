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

  it "QUERY" do
    get_symbol("QUERY").should eq(:query)
  end

  it "expands synthetic wildcard methods to concrete HTTP methods" do
    expand_synthetic_http_methods("ANY").should eq(WILDCARD_HTTP_METHODS)
    expand_synthetic_http_methods("all").should eq(WILDCARD_HTTP_METHODS)
    expand_synthetic_http_methods("*").should eq(WILDCARD_HTTP_METHODS)
  end

  it "keeps explicit methods as a single concrete method" do
    expand_synthetic_http_methods("post").should eq(["POST"])
  end

  it "only returns methods that active delivery can send" do
    requestable_http_methods("ANY").should eq(WILDCARD_HTTP_METHODS)
    requestable_http_methods("SEARCH").should eq([] of String)
  end
end
