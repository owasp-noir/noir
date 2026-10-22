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

  describe "untemplate_yaml" do
    it "blanks action-only lines and nulls templated values, keeping line count" do
      template = "{{- if .Values.on }}\nname: {{ include \"x\" . }}\nhosts:\n  - {{ .Values.host }}\n  - a.example.com\nprefix: /api\n{{- end }}\n"
      untemplated = untemplate_yaml(template)
      untemplated.should eq("\nname: ~\nhosts:\n  - ~\n  - a.example.com\nprefix: /api\n\n")
      untemplated.lines.size.should eq(template.lines.size)
    end

    it "parses a Helm template that strict YAML rejects" do
      template = "{{- if .Values.on }}\nkind: VirtualService\nhost: {{ .Values.host }}\n{{- end }}\n"
      expect_raises(YAML::ParseException) { YAML.parse_all(template) }
      docs = parse_all_yaml_template(template)
      docs.first["kind"].as_s.should eq("VirtualService")
      docs.first["host"].raw.should be_nil
    end

    it "still raises on YAML that is broken for other reasons" do
      expect_raises(YAML::ParseException) { parse_all_yaml_template("a: [1, 2\n") }
    end
  end
end
