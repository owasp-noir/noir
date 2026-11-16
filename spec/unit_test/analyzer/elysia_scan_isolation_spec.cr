require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/javascript/elysia"

private class ElysiaReadFailureProbe < Analyzer::Javascript::Elysia
  def read_file_content(path : String) : String
    raise ArgumentError.new("synthetic Elysia read failure") if File.basename(path) == "poison.ts"
    super
  end
end

describe "Elysia source scan isolation" do
  after_each do
    CodeLocator.instance.clear_all
    Noir::SkippedFiles.clear
  end

  it "keeps healthy files in input order and reports a failed file" do
    root = File.tempname("noir-elysia-isolation")
    Dir.mkdir_p(root)
    locator = CodeLocator.instance
    locator.clear_all
    Noir::SkippedFiles.clear
    %w[first poison last].each do |name|
      path = File.join(root, "#{name}.ts")
      File.write(path, "import { Elysia } from 'elysia';\nnew Elysia().get('/#{name}', () => 'ok');\n")
      locator.register_path(path)
    end
    locator.build_extension_index
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])
    options["concurrency"] = YAML::Any.new("1")

    endpoints = ElysiaReadFailureProbe.new(options).analyze
    endpoints.map(&.url).should eq(["/first", "/last"])
    failures = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis)
    failures.size.should eq(1)
    failures[0].tech.should eq("js_elysia")
    failures[0].message.should contain("synthetic Elysia read failure")
  ensure
    FileUtils.rm_rf(root) if root
  end
end
