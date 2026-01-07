require "../../../src/utils/*"

describe "json" do
  it "true" do
    valid_json?("{\"a\": 1}").should be_true
  end

  it "false" do
    valid_json?("{\"a\": 1").should be_false
  end
end
