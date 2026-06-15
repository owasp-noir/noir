require "../../../src/utils/*"

describe "yaml" do
  it "true" do
    valid_yaml?("a: 1").should be_true
  end

  it "false" do
    valid_yaml?("key: \"value").should be_false
  end

  describe "parse_yaml" do
    it "parses normal yaml unchanged" do
      parse_yaml("a: 1")["a"].as_i.should eq(1)
    end

    it "recovers from a stray tab on a blank line inside a block scalar" do
      yaml = "root:\n  desc: |-\n\t\n    line one\n  value: 42\n"
      # The raw document is rejected by libyaml...
      valid_yaml?(yaml).should be_false
      # ...but parse_yaml recovers it and the structure is intact.
      parsed = parse_yaml(yaml)
      parsed["root"]["value"].as_i.should eq(42)
    end
  end
end
