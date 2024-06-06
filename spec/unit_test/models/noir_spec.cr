require "../../../src/models/noir.cr"
require "../../../src/options.cr"
require "../../../src/models/endpoint.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = "noir"
  runner = NoirRunner.new(options)

  it "getter - options" do
    tmp_options = runner.options
    tmp_options["base"].should eq(options["base"])
  end
end

describe "Methods" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = "noir"
  options["url"] = "https://www.hahwul.com"
  options["nolog"] = "yes"
  runner = NoirRunner.new(options)

  runner.endpoints << Endpoint.new("/abcd", "GET")
  runner.endpoints << Endpoint.new("abcd", "GET")

  it "combine_url_and_endpoints" do
    runner.combine_url_and_endpoints
    runner.endpoints[0].url.should eq("https://www.hahwul.com/abcd")
    runner.endpoints[1].url.should eq("https://www.hahwul.com/abcd")
  end
end
