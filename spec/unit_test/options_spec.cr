require "../spec_helper"

describe "default_options" do
  it "init" do
    noir_options = create_test_options
    noir_options["format"].should eq("plain")
  end

  it "has base as an empty array" do
    noir_options = create_test_options
    noir_options["base"].as_a.should be_empty
  end

  it "has default native tool-calling allowlist" do
    noir_options = create_test_options
    noir_options["ai_native_tools_allowlist"].to_s.should eq("openai,xai,github")
  end
end

describe "run_options_parser" do
  it "supports multiple -b flags" do
    # Save original ARGV
    original_argv = ARGV.dup

    # Test with multiple -b flags
    ARGV.clear
    ARGV.concat(["-b", "./app1", "-b", "./app2", "-b", "./app3"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.size.should eq(3)
      noir_options["base"].as_a[0].to_s.should eq("./app1")
      noir_options["base"].as_a[1].to_s.should eq("./app2")
      noir_options["base"].as_a[2].to_s.should eq("./app3")
    ensure
      # Restore original ARGV
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports single -b flag" do
    # Save original ARGV
    original_argv = ARGV.dup

    # Test with single -b flag
    ARGV.clear
    ARGV.concat(["-b", "./single_app"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.size.should eq(1)
      noir_options["base"].as_a[0].to_s.should eq("./single_app")
    ensure
      # Restore original ARGV
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-agent flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-agent"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_agent"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-native-tools-allowlist flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-native-tools-allowlist", "openai,github"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_native_tools_allowlist"].to_s.should eq("openai,github")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-agent-max-steps flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-agent-max-steps", "10"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_agent_max_steps"].as_i.should eq(10)
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end
end
