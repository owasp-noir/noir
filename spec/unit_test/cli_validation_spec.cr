require "../spec_helper"
require "../../src/cli_validation"

describe Noir::CliValidation do
  it "rejects missing base paths" do
    options = create_test_options

    expect_raises(Noir::CliValidation::Error, /No path to scan was given/) do
      Noir::CliValidation.validate_base_paths!(options)
    end
  end

  it "rejects nonexistent base paths" do
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new("/tmp/noir-does-not-exist")])

    expect_raises(Noir::CliValidation::Error, /Base path does not exist/) do
      Noir::CliValidation.validate_base_paths!(options)
    end
  end

  it "rejects invalid output formats" do
    options = create_test_options
    options["format"] = YAML::Any.new("madeup")

    expect_raises(Noir::CliValidation::Error, /Invalid output format 'madeup'/) do
      Noir::CliValidation.validate_output_format!(options)
    end
  end

  it "rejects non-positive concurrency" do
    options = create_test_options
    options["concurrency"] = YAML::Any.new(0)

    expect_raises(Noir::CliValidation::Error, /Invalid concurrency '0'/) do
      Noir::CliValidation.validate_concurrency!(options)
    end
  end

  it "normalizes valid concurrency to an integer" do
    options = create_test_options
    options["concurrency"] = YAML::Any.new("2")

    Noir::CliValidation.validate_concurrency!(options)

    options["concurrency"].as_i.should eq(2)
  end

  it "rejects output paths in missing directories" do
    options = create_test_options
    options["output"] = YAML::Any.new("/tmp/noir-missing-dir/out.txt")

    expect_raises(Noir::CliValidation::Error, /Output directory does not exist/) do
      Noir::CliValidation.validate_output_path!(options)
    end
  end

  it "rejects unknown tagger names" do
    options = create_test_options
    options["use_taggers"] = YAML::Any.new("hunt,madeup")

    expect_raises(Noir::CliValidation::Error, /Unknown tagger/) do
      Noir::CliValidation.validate_tagger_names!(options)
    end
  end
end
