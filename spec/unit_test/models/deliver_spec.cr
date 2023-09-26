require "../../../src/models/deliver.cr"
require "../../../src/options.cr"

describe "Initialize" do
  options = default_options
  options[:base] = "noir"
  options[:send_proxy] = "http://localhost:8090"

  it "Deliver" do
    object = Deliver.new options
    object.proxy.should eq("http://localhost:8090")
  end
end
