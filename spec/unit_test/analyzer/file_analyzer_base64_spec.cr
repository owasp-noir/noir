require "../../spec_helper"
require "base64"
require "uri"
require "file_utils"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/models/code_locator"
require "../../../src/models/analyzer"
require "../../../src/analyzer/analyzers/file_analyzers/base64"

describe "Base64 FileAnalyzer hook" do
  it "detects base64-encoded URL in a file" do
    url = "http://example.com/api/secret"
    encoded = Base64.strict_encode(url)

    tmp_dir = Dir.tempdir + "/noir_b64_test_#{Random.new.hex(4)}"
    Dir.mkdir_p(tmp_dir)
    file_path = "#{tmp_dir}/test.txt"
    File.write(file_path, "some text\ndata: #{encoded}\nmore text")

    begin
      locator = CodeLocator.instance
      locator.push("file_map", file_path)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(tmp_dir)])
      options["url"] = YAML::Any.new("example.com")
      options["concurrency"] = YAML::Any.new(1)
      analyzer = FileAnalyzer.new(options)
      result = analyzer.analyze

      result.size.should eq(1)
      result[0].url.should eq("/api/secret")
      result[0].method.should eq("GET")
    ensure
      locator.try &.clear("file_map")
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "ignores non-base64 content" do
    tmp_dir = Dir.tempdir + "/noir_b64_test_#{Random.new.hex(4)}"
    Dir.mkdir_p(tmp_dir)
    file_path = "#{tmp_dir}/test.txt"
    File.write(file_path, "just normal text\nno encoded content here")

    begin
      locator = CodeLocator.instance
      locator.push("file_map", file_path)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(tmp_dir)])
      options["url"] = YAML::Any.new("example.com")
      options["concurrency"] = YAML::Any.new(1)
      analyzer = FileAnalyzer.new(options)
      result = analyzer.analyze

      result.size.should eq(0)
    ensure
      locator.try &.clear("file_map")
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "ignores base64 strings that don't contain URLs" do
    encoded = Base64.strict_encode("Hello, World! This is not a URL at all")
    tmp_dir = Dir.tempdir + "/noir_b64_test_#{Random.new.hex(4)}"
    Dir.mkdir_p(tmp_dir)
    file_path = "#{tmp_dir}/test.txt"
    File.write(file_path, encoded)

    begin
      locator = CodeLocator.instance
      locator.push("file_map", file_path)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(tmp_dir)])
      options["url"] = YAML::Any.new("example.com")
      options["concurrency"] = YAML::Any.new(1)
      analyzer = FileAnalyzer.new(options)
      result = analyzer.analyze

      result.size.should eq(0)
    ensure
      locator.try &.clear("file_map")
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "handles empty files" do
    tmp_dir = Dir.tempdir + "/noir_b64_test_#{Random.new.hex(4)}"
    Dir.mkdir_p(tmp_dir)
    file_path = "#{tmp_dir}/test.txt"
    File.write(file_path, "")

    begin
      locator = CodeLocator.instance
      locator.push("file_map", file_path)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(tmp_dir)])
      options["url"] = YAML::Any.new("example.com")
      options["concurrency"] = YAML::Any.new(1)
      analyzer = FileAnalyzer.new(options)
      result = analyzer.analyze

      result.size.should eq(0)
    ensure
      locator.try &.clear("file_map")
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
