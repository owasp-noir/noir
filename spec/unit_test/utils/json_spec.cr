require "../../../src/utils/*"

describe "json" do
  it "true" do
    json_any?("{\"a\": 1}").should_not be_nil
  end

  it "false" do
    json_any?("{\"a\": 1").should be_nil
  end
end
