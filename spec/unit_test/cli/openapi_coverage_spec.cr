require "../../spec_helper"
require "../../../src/models/noir"

private def with_coverage_scan(&)
  dir = File.tempname("noir-openapi-coverage")
  Dir.mkdir(dir)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  yield dir, options
ensure
  FileUtils.rm_rf(dir) if dir
  CodeLocator.instance.clear_all
  Noir::SkippedFiles.clear
end

private def scan_coverage(options)
  app = NoirRunner.new(options)
  app.detect
  app.analyze
  builder = OutputBuilderJson.new(options)
  builder.io = IO::Memory.new
  builder.openapi_coverage = app.openapi_coverage
  builder.analyzer_failures = app.analyzer_failures
  builder.print(app.endpoints)
  JSON.parse(builder.io.to_s)
end

describe "OpenAPI scan coverage" do
  it "distinguishes an empty paths map from a scan without an OpenAPI document" do
    with_coverage_scan do |dir, options|
      spec = File.join(dir, "openapi.json")
      File.write(spec, %({"openapi":"3.0.3","paths":{}}))
      coverage = scan_coverage(options)["coverage"]["openapi"]
      coverage["enabled_analyzers"].as_a.map(&.as_s).should eq(%w[oas2 oas3])
      coverage["documents_read"].as_i.should eq(1)
      coverage["status"].should eq("available")

      File.delete(spec)
      empty = scan_coverage(options)["coverage"]["openapi"]
      empty["status"].should eq("no_documents")
      empty["documents_read"].as_i.should eq(0)
    end
  end

  it "uses effective detector selection, explicit techs and alias-resolved exclusions" do
    with_coverage_scan do |dir, options|
      File.write(File.join(dir, "openapi.yaml"), "openapi: 3.0.3\npaths: {}\n")
      File.write(File.join(dir, "swagger.json"), %({"swagger":"2.0","paths":{}}))
      options["only_techs"] = YAML::Any.new("python_flask")
      disabled = scan_coverage(options)["coverage"]["openapi"]
      disabled["status"].should eq("disabled")
      disabled["enabled_analyzers"].as_a.should be_empty

      options["techs"] = YAML::Any.new("oas_3_0")
      forced = scan_coverage(options)["coverage"]["openapi"]
      forced["enabled_analyzers"].as_a.map(&.as_s).should eq(["oas3"])
      forced["documents_read"].as_i.should eq(1)

      options["only_techs"] = YAML::Any.new("")
      options["exclude_techs"] = YAML::Any.new("swagger,oas3")
      excluded = scan_coverage(options)["coverage"]["openapi"]
      excluded["status"].should eq("disabled")
      excluded["documents_read"].as_i.should eq(0)
    end
  end

  it "keeps partial results and records malformed JSON, YAML and paths maps" do
    with_coverage_scan do |dir, options|
      File.write(File.join(dir, "ok.yaml"), "swagger: '2.0'\npaths: {}\n")
      bad = File.join(dir, "broken")
      {"json" => %({"openapi":"3.0.3",), "yaml" => "openapi: 3.0.3\npaths: [\n",
       "yml" => "swagger: '2.0'\npaths: []\n"}.each do |ext, content|
        file = "#{bad}.#{ext}"
        File.write(file, content)
        report = scan_coverage(options)
        coverage = report["coverage"]["openapi"]
        coverage["status"].should eq("incomplete")
        coverage["documents_read"].as_i.should eq(1)
        report["errors"].as_a.should_not be_empty
        File.delete(file)
      end
    end
  end

  it "counts the root of a split document and reports unresolved references" do
    with_coverage_scan do |dir, options|
      root = File.join(dir, "openapi.json")
      fragment = File.join(dir, "books.json")
      File.write(root, %({"openapi":"3.0.3","paths":{"/books":{"$ref":"books.json#/list"}}}))
      File.write(fragment, %({"list":{"get":{"responses":{}}}}))
      report = scan_coverage(options)
      report["coverage"]["openapi"]["documents_read"].as_i.should eq(1)
      report["coverage"]["openapi"]["status"].should eq("available")
      report["endpoints"].as_a.map(&.["url"].as_s).should contain("/books")

      File.write(fragment, %({"list":"missing operation mapping"}))
      scan_coverage(options)["coverage"]["openapi"]["status"].should eq("incomplete")
      File.write(fragment, "{}")
      scan_coverage(options)["coverage"]["openapi"]["status"].should eq("incomplete")
      File.delete(fragment)
      scan_coverage(options)["coverage"]["openapi"]["status"].should eq("incomplete")
    end
  end

  it "accepts OpenAPI 3.1 components-only documents without a paths map" do
    with_coverage_scan do |dir, options|
      File.write(File.join(dir, "openapi.json"), %({"openapi":"3.1.1","components":{}}))
      report = scan_coverage(options)
      report["coverage"]["openapi"]["status"].should eq("no_documents")
      report["errors"].as_a.should be_empty
    end
  end

  it "treats a detection gap as incomplete even when no root was read" do
    with_coverage_scan do |dir, options|
      options["base"] = YAML::Any.new([YAML::Any.new(File.join(dir, "missing"))])
      scan_coverage(options)["coverage"]["openapi"]["status"].should eq("incomplete")
    end
  end
end
