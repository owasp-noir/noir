require "../../spec_helper"
require "colorize"
require "../../../src/cli/common"

describe "early CLI error colors" do
  source_files = [
    "src/options.cr",
    "src/cli_validation.cr",
    "src/models/output_builder.cr",
    "src/cli/common.cr",
  ]
  error_lines = source_files.flat_map do |path|
    File.read_lines(path).select(&.includes?(%q(STDERR.puts "ERROR:)))
  end

  it "uses red for every error path" do
    error_lines.size.should eq(14)
    error_lines.each(&.should contain(".colorize(:red)"))
  end

  it "renders errors red when colors are enabled" do
    Colorize.enabled = true

    "ERROR: invalid option".colorize(:red).to_s.should contain("\e[31m")
  ensure
    Colorize.enabled = true
  end

  it "renders errors as plain text with NO_COLOR" do
    previous_env = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = "1"
    Colorize.enabled = true
    Noir::CLI.apply_global_color_flag!([] of String)

    "ERROR: invalid option".colorize(:red).to_s.should eq("ERROR: invalid option")
  ensure
    Colorize.enabled = true
    if value = previous_env
      ENV["NO_COLOR"] = value
    else
      ENV.delete("NO_COLOR")
    end
  end
end
