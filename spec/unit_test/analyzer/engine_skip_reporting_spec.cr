require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/engines/python_engine"
require "../../../src/analyzer/engines/specification_engine"
require "../../../src/analyzer/engines/crystal_engine"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/locator_keys"
require "../../../src/models/skipped_files"

# A file an analyzer opened and could not finish must reach `errors`.
#
# `Analyzer#parallel_analyze` and `#scan_files` do record that — but three of
# the walks layered on top of them did not, each for its own reason, and the
# result was that the *same* forced failure produced `errors: []` with exit 0
# through one engine and an `errors` entry with `--strict` exit 2 through
# another:
#
#   * `parallel_python_sources` wrapped the caller's block in its own
#     `begin/rescue e -> logger.debug` *inside* the `parallel_analyze` block,
#     so the recording rescue never fired.
#   * `SpecificationEngine#each_spec_file` — the walk behind all 45
#     specification analyzers, the largest engine by subclass count — never
#     touched the channel at all.
#   * `CrystalEngine`'s action index swallowed unreadable files, costing the
#     callees of every route that dispatches through them.
#
# The subclasses below live at the top level on purpose: `initialize_analyzers`
# derives the production registry from concrete classes under `Analyzer::`, so
# a spec double declared there would join real scans.

private class SpecPythonWalk < Analyzer::Python::PythonEngine
  def tech : String
    "spec_python_engine"
  end

  def walk(&block : String -> Nil)
    parallel_python_sources { |path, _base| block.call(path) }
  end
end

private class SpecSpecificationWalk < Analyzer::Specification::SpecificationEngine
  def tech : String
    "spec_specification_engine"
  end

  def walk(key : Noir::LocatorKey(Array(String)), &block : String -> Nil)
    each_spec_file(key) { |path| block.call(path) }
  end
end

private class SpecCrystalWalk < Analyzer::Crystal::CrystalEngine
  def tech : String
    "spec_crystal_engine"
  end

  def analyze_file(path : String) : Array(Endpoint)
    [] of Endpoint
  end

  def index(paths : Array(String))
    build_crystal_action_index(paths)
  end
end

# Crystal gives every subclass its own copy of a class variable, so hooks
# registered here never reach the real `FileAnalyzer` the scan runs.
private class SpecFileAnalyzer < FileAnalyzer
end

private def spec_options(dir : String) : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  options
end

describe "engine per-file skip reporting" do
  before_each { Noir::SkippedFiles.clear }
  after_each do
    Noir::SkippedFiles.clear
    CodeLocator.instance.clear_all
  end

  it "records a Python source the caller's block could not process" do
    temp_dir = File.tempname("noir_python_engine_skip")
    Dir.mkdir_p(temp_dir)

    begin
      good = File.join(temp_dir, "good.py")
      bad = File.join(temp_dir, "bad.py")
      File.write(good, "from flask import Flask\n")
      File.write(bad, "from flask import Flask\n")

      locator = CodeLocator.instance
      locator.clear_all
      locator.register_path(good)
      locator.register_path(bad)
      locator.build_extension_index

      seen = [] of String
      SpecPythonWalk.new(spec_options(temp_dir)).walk do |path|
        raise "boom" if path == bad
        seen << path
      end

      # The isolation half of the contract is unchanged: the sibling file
      # still gets analyzed.
      seen.should eq([good])

      Noir::SkippedFiles.count.should eq(1)
      failure = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first
      failure.tech.should eq("spec_python_engine")
      failure.message.should contain(bad)
      failure.message.should contain("boom")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "records a specification document the analyzer could not process" do
    temp_dir = File.tempname("noir_spec_engine_skip")
    Dir.mkdir_p(temp_dir)

    begin
      good = File.join(temp_dir, "good.json")
      bad = File.join(temp_dir, "bad.json")
      File.write(good, %({"openapi": "3.0.0"}))
      File.write(bad, %({"openapi": "3.0.0"}))

      locator = CodeLocator.instance
      locator.clear_all
      locator.push(Noir::LocatorKeys::OAS3_JSON, good)
      locator.push(Noir::LocatorKeys::OAS3_JSON, bad)

      seen = [] of String
      SpecSpecificationWalk.new(spec_options(temp_dir)).walk(Noir::LocatorKeys::OAS3_JSON) do |path|
        raise "malformed document" if path == bad
        seen << path
      end

      seen.should eq([good])

      Noir::SkippedFiles.count.should eq(1)
      failure = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first
      failure.tech.should eq("spec_specification_engine")
      failure.message.should contain(bad)
      failure.message.should contain("malformed document")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "records a file whose FileAnalyzer hook raised" do
    temp_dir = File.tempname("noir_file_analyzer_skip")
    Dir.mkdir_p(temp_dir)

    begin
      good = File.join(temp_dir, "good.graphql")
      bad = File.join(temp_dir, "bad.graphql")
      File.write(good, "query Q { a }\n")
      File.write(bad, "query Q { a }\n")

      seen = [] of String
      SpecFileAnalyzer.add_hook(->(path : String, _url : String) do
        raise "hook exploded" if path == bad
        seen << path
        [] of Endpoint
      end, requires_url: false)

      locator = CodeLocator.instance
      locator.clear_all
      locator.register_path(good)
      locator.register_path(bad)

      SpecFileAnalyzer.new(spec_options(temp_dir)).analyze

      seen.should eq([good])

      Noir::SkippedFiles.count.should eq(1)
      failure = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first
      # The FileAnalyzer runs outside the tech registry, so it names itself
      # rather than reporting the skip under an empty tech.
      failure.tech.should eq("file_analyzer")
      failure.message.should contain(bad)
      failure.message.should contain("hook exploded")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "records a Crystal source the action index could not read" do
    temp_dir = File.tempname("noir_crystal_engine_skip")
    Dir.mkdir_p(temp_dir)
    locked = File.join(temp_dir, "locked.cr")

    begin
      readable = File.join(temp_dir, "routes.cr")
      File.write(readable, "module Routes\n  def self.home(env)\n  end\nend\n")
      File.write(locked, "module Locked\n  def self.home(env)\n  end\nend\n")
      File.chmod(locked, 0o000)

      still_readable = begin
        File.read(locked)
        true
      rescue File::Error
        false
      end
      pending! "requires a non-root user: mode 000 is not enforced here" if still_readable

      CodeLocator.instance.clear_all
      SpecCrystalWalk.new(spec_options(temp_dir)).index([readable, locked])

      Noir::SkippedFiles.count.should eq(1)
      failure = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first
      failure.tech.should eq("spec_crystal_engine")
      failure.message.should contain(locked)
    ensure
      File.chmod(locked, 0o644) if File.exists?(locked)
      FileUtils.rm_rf(temp_dir)
    end
  end
end
