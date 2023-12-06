require "../../src/options"

describe "default_options" do
  it "init" do
    noir_options = default_options()
    noir_options[:format].should eq("plain")
  end
end
