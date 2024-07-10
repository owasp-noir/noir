require "../../../src/utils/*"

describe "yaml" do
  it "true" do
    valid_yaml?("a: 1").should eq(true)
  end
  
  it "false" do
    valid_yaml?("key: \"value").should eq(false)
  end
end
