require "../../../src/utils/*"

describe "json" do
  it "true" do
    valid_json?("{\"a\": 1}").should eq(true)
  end

  it "false" do
    valid_json?("{\"a\": 1").should eq(false)
  end
end
