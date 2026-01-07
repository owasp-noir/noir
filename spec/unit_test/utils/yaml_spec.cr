require "../../../src/utils/*"

describe "yaml" do
  it "true" do
    valid_yaml?("a: 1").should be_true
  end

  it "false" do
    valid_yaml?("key: \"value").should be_false
  end
end
