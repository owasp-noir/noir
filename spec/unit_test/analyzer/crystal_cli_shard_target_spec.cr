require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

describe "crystal_cli binary name" do
  it "names the command after the shard.yml target whose main reaches the parser" do
    temp_dir = File.tempname("crystal_cli_target")
    Dir.mkdir_p(File.join(temp_dir, "src", "tool"))
    File.write(File.join(temp_dir, "shard.yml"), <<-YAML)
      name: demo
      version: 0.1.0
      targets:
        demo-tool:
          main: src/entry.cr
        demo-server:
          main: src/server.cr
      YAML
    File.write(File.join(temp_dir, "src", "entry.cr"), %(require "./tool/runner"\n))
    File.write(File.join(temp_dir, "src", "server.cr"), %(puts "up"\n))
    File.write(File.join(temp_dir, "src", "tool", "runner.cr"), <<-CRYSTAL)
      require "option_parser"
      OptionParser.parse do |parser|
        parser.on("--token TOKEN", "API token") { |t| t }
      end
      CRYSTAL

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints.select(&.method.==("CLI")).map(&.url).should eq(["cli://demo-tool"])
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
