require "../../spec_helper"
require "json"
require "yaml"
require "../../../src/cli/commands/list"

describe Noir::CLI::ListCommand do
  describe ".parse_argv" do
    it "returns subject=nil, format=text, help=false when called with no args" do
      parsed = Noir::CLI::ListCommand.parse_argv([] of String)
      parsed.subject.should be_nil
      parsed.format.should eq("text")
      parsed.help.should be_false
      parsed.errors.should be_empty
    end

    it "captures the first positional as the subject" do
      Noir::CLI::ListCommand.parse_argv(["techs"]).subject.should eq("techs")
      Noir::CLI::ListCommand.parse_argv(["taggers"]).subject.should eq("taggers")
      Noir::CLI::ListCommand.parse_argv(["formats"]).subject.should eq("formats")
    end

    it "flags -h / --help anywhere in argv" do
      Noir::CLI::ListCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::ListCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::ListCommand.parse_argv(["techs", "--help"]).help.should be_true
    end

    it "parses -f / --format (space and = forms)" do
      Noir::CLI::ListCommand.parse_argv(["techs", "-f", "json"]).format.should eq("json")
      Noir::CLI::ListCommand.parse_argv(["techs", "--format", "yaml"]).format.should eq("yaml")
      Noir::CLI::ListCommand.parse_argv(["techs", "-f=json"]).format.should eq("json")
      Noir::CLI::ListCommand.parse_argv(["techs", "--format=yaml"]).format.should eq("yaml")
    end

    it "records an error for a stray positional instead of silently ignoring it" do
      parsed = Noir::CLI::ListCommand.parse_argv(["techs", "garbage"])
      parsed.subject.should eq("techs")
      parsed.errors.should_not be_empty
    end

    it "records an error for an unknown option" do
      parsed = Noir::CLI::ListCommand.parse_argv(["techs", "--nope"])
      parsed.errors.first.should contain("--nope")
    end

    it "collects --tagger-rules paths (space and = forms) for taggers only" do
      parsed = Noir::CLI::ListCommand.parse_argv(["taggers", "--tagger-rules", "a", "--tagger-rules=b"])
      parsed.rule_paths.should eq(%w[a b])
      parsed.errors.should be_empty
      Noir::CLI::ListCommand.parse_argv(["techs", "--tagger-rules", "a"]).errors.should_not be_empty
      Noir::CLI::ListCommand.parse_argv(["taggers", "--tagger-rules"]).errors.should_not be_empty
    end

    it "records an error when -f is given without a value" do
      parsed = Noir::CLI::ListCommand.parse_argv(["techs", "-f"])
      parsed.errors.should_not be_empty
    end
  end

  describe "SUBJECTS constant" do
    it "lists every subject the run dispatcher handles" do
      Noir::CLI::ListCommand::SUBJECTS.should eq(%w[techs taggers formats])
    end
  end

  describe "LIST_FORMATS constant" do
    it "offers a human default plus the two machine formats" do
      Noir::CLI::ListCommand::LIST_FORMATS.should eq(%w[text json yaml])
    end
  end

  describe ".print_help" do
    it "names every supported subject and the format option" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_help(io)
      out = io.to_s
      %w[techs taggers formats].each { |subject| out.should contain(subject) }
      out.should contain("--format")
      # Legacy aliases should be cross-referenced so users who knew the
      # v0 names can find the v1 verb.
      out.should contain("--list-techs")
      out.should contain("--list-taggers")
    end
  end

  describe ".print_techs" do
    it "emits valid JSON carrying the synthesized callee / ai_context flags" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_techs("json", io)
      doc = JSON.parse(io.to_s)
      # go_gin now carries the schema keys that used to be missing.
      supported = doc["go_gin"]["supported"]
      supported["static_path"].as_bool.should be_false
      supported["websocket"].as_bool.should be_false
      supported["callee"].as_bool?.should_not be_nil
      supported["ai_context"]["guards"].as_bool?.should_not be_nil
      doc["go_gin"]["view"].should eq("code")
      doc["nginx"]["view"].should eq("gateway")
    end

    it "emits valid YAML" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_techs("yaml", io)
      doc = YAML.parse(io.to_s)
      doc["js_express"]["supported"]["callee"].as_bool.should be_true
    end

    it "renders nested params and lists in the text view, not Crystal inspect" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_techs("text", io)
      out = io.to_s.gsub(/\e\[[0-9;]*m/, "")
      out.should_not contain("=>")
      out.should_not contain("[\"")
      out.should contain("similar: asp, classic-asp")
      out.should match(/^     params:\n       query: true$/m)
      out.should match(/^       guards: (true|false)$/m)
    end
  end

  describe ".print_taggers" do
    it "emits JSON without leaking the internal :runner class reference" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_taggers("json", io)
      doc = JSON.parse(io.to_s)
      doc["taggers"].as_a.each do |tagger|
        tagger.as_h.has_key?("runner").should be_false
        tagger["id"].as_s.should_not be_empty
      end
      doc.as_h.has_key?("custom_taggers").should be_false
    end

    it "adds custom rules, with their file and example check, when given" do
      yaml = <<-YAML
        key: team_internal
        name: Internal Tagger
        summary: Internal routes
        order: 115
        tag: { tagger: Internal, description: internal }
        match: { path_segment: internal }
        examples: { match: [{ url: /internal }, { url: /public }], no_match: [{ url: /api }] }
        YAML
      rules = [NoirTagRules.parse(yaml, "team.yml")]

      io = IO::Memory.new
      Noir::CLI::ListCommand.print_taggers("json", io, custom_rules: rules)
      custom = JSON.parse(io.to_s)["custom_taggers"].as_a
      custom.map(&.["id"].as_s).should eq(["team_internal"])
      custom[0]["file"].as_s.should eq("team.yml")
      custom[0]["example_failures"].as_a.map(&.as_s).should eq(["not tagged: GET /public (http)"])

      io = IO::Memory.new
      Noir::CLI::ListCommand.print_taggers("text", io, custom_rules: rules)
      text = io.to_s
      text.should contain("Custom tag rules (--tagger-rules):")
      text.should contain("team_internal")
      text.should contain("not tagged: GET /public (http)")
    end
  end

  describe ".print_formats" do
    it "emits the same catalog as the text view, as JSON" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_formats("json", io)
      doc = JSON.parse(io.to_s)
      doc["formats"].as_a.map(&.as_s).should eq(Noir::OutputFormats::NAMES)
    end
  end
end
