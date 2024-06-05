require "../../src/options"

describe "default_options" do
  it "init" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["format"].should eq("plain")
  end
end
