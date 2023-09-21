require "../../../../src/models/delivers/zap.cr"
require "../../../../src/options.cr"

describe "Initialize" do
  zap = ZAP.new "http://localhost:8090"

  it "init" do
    zap.nil?.should eq(false)
  end
end
