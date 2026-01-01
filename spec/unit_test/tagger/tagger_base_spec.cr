require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/endpoint.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/tagger.cr"
require "yaml"

TAGGER_BASE_FIXTURE_PATH = File.join(__DIR__, "taggers", "fixtures", "sample_python_app.py")

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

# Test implementation to access protected methods
class TestTagger < Tagger
  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "test"
  end

  def test_read_source_code(path : String) : String?
    read_source_code(path)
  end

  def test_read_source_context(path_info : PathInfo, context_lines : Int32 = 10) : Tuple(Array(String), String?, Array(String))?
    read_source_context(path_info, context_lines)
  end

  def test_get_endpoint_source_code(endpoint : Endpoint) : Array(Tuple(PathInfo, String))
    get_endpoint_source_code(endpoint)
  end

  def test_source_contains_pattern?(endpoint : Endpoint, pattern : Regex, context_lines : Int32 = 20) : Bool
    source_contains_pattern?(endpoint, pattern, context_lines)
  end

  def test_extract_from_source(endpoint : Endpoint, pattern : Regex, context_lines : Int32 = 20) : Array(Regex::MatchData)
    extract_from_source(endpoint, pattern, context_lines)
  end
end

describe "Tagger" do
  describe "source code helper methods" do
    describe "read_source_code" do
      it "reads and caches file content" do
        tagger = TestTagger.new(default_tagger_options)

        content = tagger.test_read_source_code(TAGGER_BASE_FIXTURE_PATH)
        content.should_not be_nil
        content.not_nil!.should contain("from flask import Flask")

        # Second read should return cached content
        content2 = tagger.test_read_source_code(TAGGER_BASE_FIXTURE_PATH)
        content2.should eq(content)
      end

      it "returns nil for non-existent file" do
        tagger = TestTagger.new(default_tagger_options)

        content = tagger.test_read_source_code("/non/existent/file.py")
        content.should be_nil
      end
    end

    describe "read_source_context" do
      it "returns context lines around target line" do
        tagger = TestTagger.new(default_tagger_options)

        path_info = PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 8) # @app.route('/api/v1/old_endpoint'...
        context = tagger.test_read_source_context(path_info, 3)

        context.should_not be_nil
        lines_before, target_line, lines_after = context.not_nil!

        # Should have lines before
        lines_before.size.should be > 0

        # Target line should be the route decorator
        target_line.not_nil!.should contain("@app.route")

        # Should have lines after
        lines_after.size.should be > 0
      end

      it "returns nil for nil line number" do
        tagger = TestTagger.new(default_tagger_options)

        path_info = PathInfo.new(TAGGER_BASE_FIXTURE_PATH)
        context = tagger.test_read_source_context(path_info)

        context.should be_nil
      end

      it "returns nil for non-existent file" do
        tagger = TestTagger.new(default_tagger_options)

        path_info = PathInfo.new("/non/existent/file.py", 1)
        context = tagger.test_read_source_context(path_info)

        context.should be_nil
      end

      it "handles line at start of file" do
        tagger = TestTagger.new(default_tagger_options)

        path_info = PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 1)
        context = tagger.test_read_source_context(path_info, 5)

        context.should_not be_nil
        lines_before, _target_line, _lines_after = context.not_nil!

        lines_before.size.should eq(0) # No lines before first line
      end
    end

    describe "get_endpoint_source_code" do
      it "returns source code for endpoint code paths" do
        tagger = TestTagger.new(default_tagger_options)

        details = Details.new(PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 8))
        endpoint = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details)

        sources = tagger.test_get_endpoint_source_code(endpoint)
        sources.size.should eq(1)
        sources[0][1].should contain("from flask import Flask")
      end

      it "returns empty array for endpoint without code paths" do
        tagger = TestTagger.new(default_tagger_options)

        endpoint = Endpoint.new("/api/test", "GET")

        sources = tagger.test_get_endpoint_source_code(endpoint)
        sources.size.should eq(0)
      end
    end

    describe "source_contains_pattern?" do
      it "returns true when pattern is found in source context" do
        tagger = TestTagger.new(default_tagger_options)

        details = Details.new(PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 8))
        endpoint = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details)

        result = tagger.test_source_contains_pattern?(endpoint, /@deprecated/i)
        result.should be_true
      end

      it "returns false when pattern is not found" do
        tagger = TestTagger.new(default_tagger_options)

        details = Details.new(PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 92)) # public_endpoint
        endpoint = Endpoint.new("/api/public", "GET", [] of Param, details)

        result = tagger.test_source_contains_pattern?(endpoint, /@deprecated/i)
        result.should be_false
      end

      it "returns false for endpoint without code paths" do
        tagger = TestTagger.new(default_tagger_options)

        endpoint = Endpoint.new("/api/test", "GET")

        result = tagger.test_source_contains_pattern?(endpoint, /@deprecated/i)
        result.should be_false
      end
    end

    describe "extract_from_source" do
      it "extracts matching groups from source" do
        tagger = TestTagger.new(default_tagger_options)

        details = Details.new(PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 8))
        endpoint = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details)

        matches = tagger.test_extract_from_source(endpoint, /@app\.route\('([^']+)'/)
        matches.size.should be > 0
      end

      it "returns empty array when no matches found" do
        tagger = TestTagger.new(default_tagger_options)

        details = Details.new(PathInfo.new(TAGGER_BASE_FIXTURE_PATH, 8))
        endpoint = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details)

        matches = tagger.test_extract_from_source(endpoint, /NONEXISTENT_PATTERN_12345/)
        matches.size.should eq(0)
      end
    end
  end
end
