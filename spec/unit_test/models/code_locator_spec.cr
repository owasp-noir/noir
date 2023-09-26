require "../../../src/models/code_locator.cr"
require "../../../src/options.cr"

describe "Initialize" do
  locator = CodeLocator.new

  it "getter/setter - string" do
    locator.set "unittest", "abcd"
    locator.get("unittest").should eq("abcd")
  end

  it "all/push - array" do
    locator.push "unittest", "abcd"
    locator.push "unittest", "bbbb"
    locator.all("unittest").should eq(["abcd", "bbbb"])
  end
end
