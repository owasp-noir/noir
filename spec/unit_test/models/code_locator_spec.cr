require "../../../src/models/code_locator.cr"
require "../../../src/options.cr"

describe "Initialize" do
  locator = CodeLocator.new

  it "getter/setter - name" do
    locator.set "unittest", "abcd"
    locator.get("unittest").should eq("abcd")
  end
end
