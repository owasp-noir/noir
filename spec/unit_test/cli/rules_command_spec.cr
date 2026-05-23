require "../../spec_helper"
require "file_utils"
require "../../../src/cli/commands/rules"

# Isolated NOIR_HOME so each spec sees a clean rules directory.
private def with_isolated_rules_home(&)
  prev = ENV["NOIR_HOME"]?
  tmp = File.tempname("noir-rules-cli-spec")
  Dir.mkdir_p(tmp)
  ENV["NOIR_HOME"] = tmp
  begin
    yield tmp
  ensure
    if prev
      ENV["NOIR_HOME"] = prev
    else
      ENV.delete("NOIR_HOME")
    end
    FileUtils.rm_rf(tmp)
  end
end

describe Noir::CLI::RulesCommand do
  describe ".parse_argv" do
    it "treats no args as 'show help'" do
      parsed = Noir::CLI::RulesCommand.parse_argv([] of String)
      parsed.action.should be_nil
      parsed.help.should be_false
    end

    it "captures the first positional as the action" do
      Noir::CLI::RulesCommand.parse_argv(["list"]).action.should eq("list")
      Noir::CLI::RulesCommand.parse_argv(["update"]).action.should eq("update")
      Noir::CLI::RulesCommand.parse_argv(["path"]).action.should eq("path")
    end

    it "first positional wins when extra args follow" do
      # `rules update` ignores positionals — confirm parser doesn't
      # accidentally promote a later argument to action.
      Noir::CLI::RulesCommand.parse_argv(["update", "force"]).action.should eq("update")
    end

    it "flags -h / --help anywhere" do
      Noir::CLI::RulesCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::RulesCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::RulesCommand.parse_argv(["update", "--help"]).help.should be_true
    end
  end

  describe ".rules_path" do
    it "lives under NOIR_HOME/passive_rules" do
      with_isolated_rules_home do |home|
        Noir::CLI::RulesCommand.rules_path.should eq(File.join(home, "passive_rules"))
      end
    end
  end

  describe ".list_rules" do
    it "prints a hint when the rules directory doesn't exist yet" do
      with_isolated_rules_home do |_|
        # NOIR_HOME exists but passive_rules subdirectory does not
        io = IO::Memory.new
        Noir::CLI::RulesCommand.list_rules(io)
        out = io.to_s
        out.should contain("Rules directory does not exist")
        out.should contain("noir rules update")
      end
    end

    it "prints a hint when the directory exists but is empty" do
      with_isolated_rules_home do |home|
        Dir.mkdir_p(File.join(home, "passive_rules"))
        io = IO::Memory.new
        Noir::CLI::RulesCommand.list_rules(io)
        out = io.to_s
        out.should contain("No rule files found")
        out.should contain("noir rules update")
      end
    end

    it "lists yaml/yml rule files recursively with a count" do
      with_isolated_rules_home do |home|
        rules_dir = File.join(home, "passive_rules")
        Dir.mkdir_p(File.join(rules_dir, "category"))
        File.write(File.join(rules_dir, "top.yaml"), "id: top\n")
        File.write(File.join(rules_dir, "alt.yml"), "id: alt\n")
        File.write(File.join(rules_dir, "category", "nested.yaml"), "id: nested\n")
        # Non-yaml file must not appear in the listing.
        File.write(File.join(rules_dir, "README.md"), "")

        io = IO::Memory.new
        Noir::CLI::RulesCommand.list_rules(io)
        out = io.to_s

        out.should contain("Rule files (3):")
        out.should contain("top.yaml")
        out.should contain("alt.yml")
        out.should contain("category/nested.yaml")
        out.should_not contain("README.md")
      end
    end

    it "shows entries as paths relative to the rules root" do
      with_isolated_rules_home do |home|
        rules_dir = File.join(home, "passive_rules")
        Dir.mkdir_p(File.join(rules_dir, "deep", "tree"))
        File.write(File.join(rules_dir, "deep", "tree", "leaf.yaml"), "id: leaf\n")

        io = IO::Memory.new
        Noir::CLI::RulesCommand.list_rules(io)
        out = io.to_s

        # Output must be relative, not the absolute path
        out.should contain("deep/tree/leaf.yaml")
        out.should_not contain("#{rules_dir}/deep")
      end
    end
  end

  describe ".print_help" do
    it "names every supported action" do
      io = IO::Memory.new
      Noir::CLI::RulesCommand.print_help(io)
      out = io.to_s
      %w[list update path].each { |action| out.should contain(action) }
      out.should contain("--passive-scan-path")
      out.should contain("NOIR_HOME")
    end
  end
end
