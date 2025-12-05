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
end
