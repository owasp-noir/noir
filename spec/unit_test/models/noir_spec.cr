require "../../../src/models/noir.cr"
require "../../../src/options.cr"
require "../../../src/models/endpoint.cr"

describe "Initialize" do
  options = default_options
  options[:base] = "noir"
  runner = NoirRunner.new(options)

  it "getter - options" do
    tmp_options = runner.options
    tmp_options[:base].should eq(options[:base])
  end
end

describe "Methods" do
    options = default_options
    options[:base] = "noir"
    options[:url] = "https://www.hahwul.com"
    runner = NoirRunner.new(options)

    tmp_endpoint = Endpoint.new("/abcd", "GET")
    runner.endpoints << tmp_endpoint
  
    it "combine_url_and_endpoints" do
      runner.combine_url_and_endpoints
      runner.endpoints[0].url.should eq("https://www.hahwul.com/abcd")
    end
  end
  