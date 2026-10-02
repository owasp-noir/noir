require "../../../src/utils/*"

describe "yaml" do
  it "true" do
    yaml_any?("a: 1").should_not be_nil
  end

  it "false" do
    yaml_any?("key: \"value").should be_nil
  end

  describe "parse_yaml" do
    it "parses normal yaml unchanged" do
      parse_yaml("a: 1")["a"].as_i.should eq(1)
    end

    it "recovers from a stray tab on a blank line inside a block scalar" do
      yaml = "root:\n  desc: |-\n\t\n    line one\n  value: 42\n"
      # The raw document is rejected by libyaml...
      yaml_any?(yaml).should be_nil
      # ...but parse_yaml recovers it and the structure is intact.
      parsed = parse_yaml(yaml)
      parsed["root"]["value"].as_i.should eq(42)
    end
  end
end
