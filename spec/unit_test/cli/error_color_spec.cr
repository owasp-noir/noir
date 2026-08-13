require "../../spec_helper"
require "colorize"
require "../../../src/cli/common"

describe "early CLI error colors" do
  # Read inside the example, not in the `describe` body.
  #
  # These are repo-relative paths, so from any working directory other than
  # the repo root `File.read_lines` raises — and in the `describe` body that
  # is collection time, which `spec/AGENTS.md` singles out: Crystal installs
  # its runner with `at_exit` and skips it when the process is already
  # exiting on an error, so one raise there took down all ~4,750 examples and
  # reported `0 examples` — no failure, no name, nothing to grep.
  #
  # The sibling source-scanning specs (`layering_boundary_spec.cr`,
  # `detector_coverage_spec.cr`, and five others) are CWD-relative too, but
  # they all use `Dir.glob`, which returns an empty list rather than raising,
  # and each carries a "guards the guard" size assertion so a wrong CWD fails
  # loudly. This one both raised and skipped that discipline.
  it "uses red for every error path" do
    source_files = [
      "src/options.cr",
      "src/cli_validation.cr",
      "src/models/output_builder.cr",
      "src/cli/common.cr",
    ]
    error_lines = source_files.flat_map do |path|
      File.read_lines(path).select(&.includes?(%q(STDERR.puts "ERROR:)))
    end

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
