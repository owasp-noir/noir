require "../../spec_helper"
require "../../../src/output_builder/formats"
require "../../../src/cli_validation"
require "../../../src/completions"

# The catalog is derived from the `Noir::OutputFormat` annotation on each
# builder, so these examples guard the derivation itself: that it stays
# non-empty and unambiguous, and that everything downstream of it (`-f`
# validation, the completion scripts) really does read the same list rather
# than a copy that drifted.
describe Noir::OutputFormats do
  it "derives one entry per annotated builder, with a description" do
    Noir::OutputFormats::ENTRIES.size.should be > 1
    Noir::OutputFormats::ENTRIES.each do |entry|
      entry.name.should_not be_empty
      entry.description.should_not be_empty
    end
  end

  it "has no duplicate format names" do
    names = Noir::OutputFormats::NAMES
    names.uniq.size.should eq(names.size)
  end

  it "includes the default format" do
    Noir::OutputFormats.known?(Noir::OutputFormats::DEFAULT).should be_true
  end

  it "rejects an unknown format" do
    Noir::OutputFormats.known?("nope").should be_false
  end

  it "reports an unrenderable format instead of silently emitting nothing" do
    rendered = Noir::OutputFormats.render(
      "nope",
      {"debug" => YAML::Any.new(false), "verbose" => YAML::Any.new(false),
       "color" => YAML::Any.new(false), "nolog" => YAML::Any.new(true),
       "output" => YAML::Any.new("")},
      [] of Endpoint,
      [] of PassiveScanResult
    )
    rendered.should be_false
  end

  it "lists every format in the -f help text" do
    help = Noir::OutputFormats.help_text
    Noir::OutputFormats::ENTRIES.each do |entry|
      help.should contain(entry.name)
      help.should contain(entry.description)
    end
  end

  it "offers every format in every shell completion" do
    scripts = {
      "zsh"    => Noir::Completions::Zsh.script,
      "bash"   => Noir::Completions::Bash.script,
      "fish"   => Noir::Completions::Fish.script,
      "elvish" => Noir::Completions::Elvish.script,
    }
    # Elvish completes `-f` by file, not by an enum list, so only the three
    # shells whose scripts carry the value list are asserted here.
    %w[zsh bash fish].each do |shell|
      Noir::OutputFormats::NAMES.each do |name|
        scripts[shell].should contain(name)
      end
    end
  end

  it "accepts every catalog format at the CLI validation gate" do
    Noir::OutputFormats::NAMES.each do |name|
      options = {"format" => YAML::Any.new(name)}
      Noir::CliValidation.validate_output_format!(options)
    end
  end
end
