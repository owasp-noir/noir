require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/endpoint.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/framework_tagger.cr"
require "yaml"

describe FrameworkTagger do
  describe "target_techs" do
    it "returns empty array by default" do
      FrameworkTagger.target_techs.should eq([] of String)
    end
  end

  describe "initialization" do
    it "creates framework tagger with options" do
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new("/tmp/test")])
      tagger = FrameworkTagger.new(options)
      tagger.should_not be_nil
    end
  end

  describe "read_file" do
    it "reads an existing file" do
      # Create a temp file for testing
      tmp_path = File.tempfile("noir_test", ".txt") do |file|
        file.print("test content")
      end

      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
        tagger = FrameworkTagger.new(options)
        content = tagger.read_file(tmp_path.path)
        content.should eq("test content")
      ensure
        tmp_path.delete
      end
    end

    it "returns nil for non-existent file" do
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
      tagger = FrameworkTagger.new(options)
      content = tagger.read_file("/nonexistent/file.txt")
      content.should be_nil
    end

    it "caches file content" do
      tmp_path = File.tempfile("noir_test", ".txt") do |file|
        file.print("cached content")
      end

      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
        tagger = FrameworkTagger.new(options)

        # Read once to populate the cache
        content1 = tagger.read_file(tmp_path.path)
        content1.should eq("cached content")

        # Modify file on disk, then read again - should return cached value
        File.write(tmp_path.path, "updated content")
        content2 = tagger.read_file(tmp_path.path)
        content2.should eq("cached content")
      ensure
        tmp_path.delete
      end
    end
  end

  describe "read_source_context" do
    it "returns source contexts for endpoint with code paths" do
      tmp_path = File.tempfile("noir_test", ".cr") do |file|
        file.print("get '/api/users' do\n  users\nend")
      end

      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
        tagger = FrameworkTagger.new(options)

        details = Details.new(PathInfo.new(tmp_path.path, 1))
        endpoint = Endpoint.new("/api/users", "GET", details)

        contexts = tagger.read_source_context(endpoint)
        contexts.size.should eq(1)
        contexts[0].path.should eq(tmp_path.path)
        contexts[0].line.should eq(1)
        contexts[0].full_content.should contain("get '/api/users'")
      ensure
        tmp_path.delete
      end
    end

    it "returns empty array for endpoint with non-existent code path" do
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
      tagger = FrameworkTagger.new(options)

      details = Details.new(PathInfo.new("/nonexistent/file.cr", 1))
      endpoint = Endpoint.new("/api/test", "GET", details)

      contexts = tagger.read_source_context(endpoint)
      contexts.size.should eq(0)
    end

    it "returns empty array for endpoint with no code paths" do
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new("/tmp")])
      tagger = FrameworkTagger.new(options)

      endpoint = Endpoint.new("/api/test", "GET")
      contexts = tagger.read_source_context(endpoint)
      contexts.size.should eq(0)
    end
  end
end

describe SourceContext do
  it "stores path, line, and content" do
    ctx = SourceContext.new(path: "/test.cr", line: 42, full_content: "puts hello")
    ctx.path.should eq("/test.cr")
    ctx.line.should eq(42)
    ctx.full_content.should eq("puts hello")
  end

  it "allows nil line number" do
    ctx = SourceContext.new(path: "/test.cr", line: nil, full_content: "content")
    ctx.line.should be_nil
  end
end
