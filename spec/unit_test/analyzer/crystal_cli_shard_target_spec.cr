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

describe "crystal_cli subcommands named by an ARGV comparison" do
  it "scopes reads guarded by the comparison's variable to that subcommand" do
    temp_dir = File.tempname("crystal_cli_guard")
    Dir.mkdir_p(File.join(temp_dir, "src"))
    File.write(File.join(temp_dir, "src", "jobs.cr"), <<-CRYSTAL)
      require "option_parser"

      export = ARGV[0]? == "export-items" && ARGV[1]?
      notify = ARGV[0]? == "notify-orders"
      if ARGV == ["prune"]
        puts "prune"
      elsif export
        OptionParser.parse(ARGV[2..]) do |parser|
          parser.on("--apply", "Apply") { puts "apply" }
        end
      elsif notify
        raise ArgumentError.new unless ARGV == ["notify-orders"] || ARGV == ["notify-orders", "--all"]
        OptionParser.parse(ARGV[1..]) do |parser|
          parser.on("--order ID", "Order") { |v| puts v }
        end
      else
        exit 2
      end
      ready = true
      if export && ready
        puts ARGV[2]
      end
      CRYSTAL

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    params = runner.endpoints.select(&.method.==("CLI")).to_h { |e| {e.url, e.params.map(&.name).sort!} }
    (params.delete("cli://jobs") || [] of String).should be_empty
    params.should eq({
      "cli://jobs/prune"         => [] of String,
      "cli://jobs/export-items"  => ["apply", "arg0", "arg1"],
      "cli://jobs/notify-orders" => ["all", "order"],
    })
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "keeps reads on the root when the guard is not a plain equality" do
    temp_dir = File.tempname("crystal_cli_guard_other")
    Dir.mkdir_p(File.join(temp_dir, "src"))
    File.write(File.join(temp_dir, "src", "jobs.cr"), <<-CRYSTAL)
      require "option_parser"

      interactive = ARGV[0]? != "batch"
      if interactive
        puts ARGV[0]
      end
      mode = ARGV[0]? == "sync" ? :sync : :async
      if mode
        puts ARGV[1]
      end
      verbose = ARGV[0]? == "verbose"
      verbose = false
      if verbose
        puts ARGV[2]
      end
      CRYSTAL

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    params = runner.endpoints.select(&.method.==("CLI")).to_h { |e| {e.url, e.params.map(&.name).sort!} }
    params["cli://jobs"].should eq(["arg0", "arg1", "arg2"])
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
