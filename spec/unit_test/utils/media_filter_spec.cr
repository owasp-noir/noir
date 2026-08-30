require "../../spec_helper"
require "../../../src/utils/media_filter"

# NOTE: Predicate methods renamed:
#   is_media_file?   -> media_file?
#   is_file_too_large? -> file_too_large?
# Tests updated accordingly.

# A file that reports `size` bytes without writing them: `truncate` leaves a
# hole, so the size gate can be exercised at 10MB+ without a 10MB write per
# example. The bytes it reads back are NUL, which is why the callers below
# pass `sniff_binary: false` — the same way the detector walk calls
# `skip_check`.
private def sparse_file(extension : String, size : Int64) : String
  path = File.tempname("noir_size_budget", extension)
  File.open(path, "w", &.truncate(size))
  path
end

describe MediaFilter do
  describe ".media_file?" do
    it "should detect image files" do
      MediaFilter.media_file?("test.jpg").should be_true
      MediaFilter.media_file?("test.png").should be_true
      MediaFilter.media_file?("test.gif").should be_true
      MediaFilter.media_file?("test.svg").should be_true
      MediaFilter.media_file?("TEST.JPG").should be_true # Case insensitive
    end

    it "should detect video files" do
      MediaFilter.media_file?("test.mp4").should be_true
      MediaFilter.media_file?("test.avi").should be_true
      MediaFilter.media_file?("test.mkv").should be_true
      MediaFilter.media_file?("test.MOV").should be_true # Case insensitive
    end

    it "should detect audio files" do
      MediaFilter.media_file?("test.mp3").should be_true
      MediaFilter.media_file?("test.wav").should be_true
      MediaFilter.media_file?("test.flac").should be_true
    end

    it "should detect archive files" do
      MediaFilter.media_file?("test.zip").should be_true
      MediaFilter.media_file?("test.rar").should be_true
      MediaFilter.media_file?("test.tar.gz").should be_true # .gz is in media extensions
      MediaFilter.media_file?("test.gz").should be_true
    end

    it "should not detect source code files" do
      MediaFilter.media_file?("test.cr").should be_false
      MediaFilter.media_file?("test.js").should be_false
      MediaFilter.media_file?("test.ts").should be_false # TypeScript files should not be skipped
      MediaFilter.media_file?("test.py").should be_false
      MediaFilter.media_file?("test.rb").should be_false
      MediaFilter.media_file?("test.java").should be_false
    end

    it "should not detect configuration files" do
      MediaFilter.media_file?("test.yml").should be_false
      MediaFilter.media_file?("test.json").should be_false
      MediaFilter.media_file?("test.xml").should be_false
      MediaFilter.media_file?("test.txt").should be_false
    end

    it "should handle files without extensions" do
      MediaFilter.media_file?("test").should be_false
      MediaFilter.media_file?("Dockerfile").should be_false
      MediaFilter.media_file?("README").should be_false
    end
  end

  describe ".file_too_large?" do
    it "should return false for non-existent files" do
      MediaFilter.file_too_large?("non_existent_file.txt").should be_false
    end

    it "should check file size against default limit" do
      # Create a temporary small file
      temp_file = File.tempname("noir_media_small", ".txt")
      File.write(temp_file, "small content")

      MediaFilter.file_too_large?(temp_file).should be_false

      File.delete(temp_file) if File.exists?(temp_file)
    end

    it "should check file size against custom limit" do
      # Create a temporary file
      temp_file = File.tempname("noir_media_custom", ".txt")
      File.write(temp_file, "test content")

      # Should be under 1KB limit
      MediaFilter.file_too_large?(temp_file, 1024).should be_false

      # Should be over 5 byte limit
      MediaFilter.file_too_large?(temp_file, 5).should be_true

      File.delete(temp_file) if File.exists?(temp_file)
    end
  end

  describe ".should_skip_file?" do
    it "should skip media files regardless of size" do
      MediaFilter.should_skip_file?("test.jpg").should be_true
      MediaFilter.should_skip_file?("test.mp4").should be_true
      MediaFilter.should_skip_file?("test.mp3").should be_true
    end

    it "should not skip source code files by extension" do
      MediaFilter.should_skip_file?("test.cr").should be_false
      MediaFilter.should_skip_file?("test.js").should be_false
      MediaFilter.should_skip_file?("test.py").should be_false
    end

    it "should handle combination of extension and size checks" do
      # Create a temporary source file that's large
      temp_file = File.tempname("noir_media_large", ".cr")
      File.write(temp_file, "# " + "x" * 1000) # Make it large enough

      # Should skip due to size even though it's a source file
      MediaFilter.should_skip_file?(temp_file, 500).should be_true

      # Should not skip with larger size limit
      MediaFilter.should_skip_file?(temp_file, 2000).should be_false

      File.delete(temp_file) if File.exists?(temp_file)
    end
  end

  describe ".skip_reason" do
    it "should return nil for files that shouldn't be skipped" do
      MediaFilter.skip_reason("test.cr").should be_nil
      MediaFilter.skip_reason("test.js").should be_nil
    end

    it "should return media file reason" do
      reason = MediaFilter.skip_reason("test.jpg")
      reason.should_not be_nil
      reason.as(String).should contain("media file")
      reason.as(String).should contain(".jpg")
    end

    it "should return file size reason for large files" do
      temp_file = File.tempname("noir_media_size", ".txt")
      File.write(temp_file, "x" * 100)

      reason = MediaFilter.skip_reason(temp_file, 50)
      reason.should_not be_nil
      reason.as(String).should contain("file too large")

      File.delete(temp_file) if File.exists?(temp_file)
    end
  end

  describe ".binary_content_signature?" do
    it "returns false for plain text content" do
      temp = "/tmp/noir-binsig-text-#{Random.rand(1_000_000)}.py"
      File.write(temp, "def hello():\n    return 'hi'\n")
      begin
        MediaFilter.binary_content_signature?(temp).should be_false
      ensure
        File.delete(temp) if File.exists?(temp)
      end
    end

    it "returns true for content containing NUL bytes" do
      temp = "/tmp/noir-binsig-bin-#{Random.rand(1_000_000)}.py"
      # `dd` style random bytes — virtually certain to contain a NUL
      # in 1KB. Use a deterministic NUL-bearing payload so the test
      # isn't probabilistic.
      File.write(temp, "header\x00\x01\x02binary\x00content")
      begin
        MediaFilter.binary_content_signature?(temp).should be_true
      ensure
        File.delete(temp) if File.exists?(temp)
      end
    end

    it "returns false for empty files (nothing to sample)" do
      temp = "/tmp/noir-binsig-empty-#{Random.rand(1_000_000)}.py"
      File.write(temp, "")
      begin
        MediaFilter.binary_content_signature?(temp).should be_false
      ensure
        File.delete(temp) if File.exists?(temp)
      end
    end

    it "returns false on unreadable paths (graceful)" do
      MediaFilter.binary_content_signature?("/nonexistent-path-#{Random.rand(1_000_000)}").should be_false
    end
  end

  describe ".skip_check (binary content)" do
    it "skips a text-extension file whose bytes look binary" do
      # The dogfood case: a `.py` file that's actually random binary
      # bytes (e.g. accidentally renamed object file, packed asset
      # with the wrong extension) used to take Crystal regexes down
      # with `ArgumentError: UTF-8 error: code points greater than
      # 0x10ffff are not defined`. The binary-sniff in skip_check
      # catches it before any analyzer regex runs.
      temp = "/tmp/noir-skip-binary-#{Random.rand(1_000_000)}.py"
      File.write(temp, "import os\x00\x01\x02unparseable")
      begin
        reason = MediaFilter.skip_check(temp)
        reason.should_not be_nil
        reason.as(String).should contain("binary content")
      ensure
        File.delete(temp) if File.exists?(temp)
      end
    end

    it "does not skip ordinary text source files" do
      temp = "/tmp/noir-skip-text-#{Random.rand(1_000_000)}.py"
      File.write(temp, "from flask import Flask\napp = Flask(__name__)\n")
      begin
        MediaFilter.skip_check(temp).should be_nil
      ensure
        File.delete(temp) if File.exists?(temp)
      end
    end
  end

  describe ".spec_document?" do
    it "recognizes specification and structured document extensions" do
      MediaFilter.spec_document?("openapi.json").should be_true
      MediaFilter.spec_document?("swagger.YAML").should be_true # Case insensitive
      MediaFilter.spec_document?("service.wsdl").should be_true
      MediaFilter.spec_document?("burp-export.xml").should be_true
      MediaFilter.spec_document?("schema.graphql").should be_true
    end

    it "does not treat source code or media as a specification document" do
      MediaFilter.spec_document?("bundle.js").should be_false
      MediaFilter.spec_document?("views.py").should be_false
      MediaFilter.spec_document?("logo.png").should be_false
    end
  end

  describe ".max_size_for" do
    it "gives specification documents the larger budget" do
      MediaFilter::MAX_SPEC_FILE_SIZE.should be >= MediaFilter::MAX_FILE_SIZE
      MediaFilter.max_size_for("openapi.json").should eq(MediaFilter::MAX_SPEC_FILE_SIZE)
      MediaFilter.max_size_for("k8s/ingress.yaml").should eq(MediaFilter::MAX_SPEC_FILE_SIZE)
    end

    it "keeps everything else on the media cap" do
      MediaFilter.max_size_for("app.py").should eq(MediaFilter::MAX_FILE_SIZE)
      MediaFilter.max_size_for("logo.png").should eq(MediaFilter::MAX_FILE_SIZE)
    end
  end

  describe "specification document budget" do
    it "reads a specification document past the media cap" do
      # The NetBox case: a 12MB generated `openapi.json` describing 308
      # paths was dropped by a filter meant to keep image files out of the scan.
      path = sparse_file(".json", MediaFilter::MAX_FILE_SIZE.to_i64 + 1)
      begin
        MediaFilter.skip_check(path, sniff_binary: false).should be_nil
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "still applies the media cap to source files of the same size" do
      path = sparse_file(".py", MediaFilter::MAX_FILE_SIZE.to_i64 + 1)
      begin
        reason = MediaFilter.skip_check(path, sniff_binary: false)
        reason.should_not be_nil
        reason.as(String).should contain("file too large")
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "reports the budget that was actually applied" do
      path = sparse_file(".json", MediaFilter::MAX_SPEC_FILE_SIZE.to_i64 + 1)
      begin
        reason = MediaFilter.skip_check(path, sniff_binary: false)
        reason.should_not be_nil
        expected_mb = (MediaFilter::MAX_SPEC_FILE_SIZE / (1024.0 * 1024.0)).round(2)
        reason.as(String).should contain("file too large")
        reason.as(String).should contain("> #{expected_mb}MB")
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end

  describe ".env_size" do
    it "returns the default when the variable is unset" do
      ENV.delete("NOIR_SPEC_ENV_SIZE_TEST")
      MediaFilter.env_size("NOIR_SPEC_ENV_SIZE_TEST", 1234).should eq(1234)
    end

    it "parses the same value syntax as NOIR_MAX_FILE_SIZE" do
      ENV["NOIR_SPEC_ENV_SIZE_TEST"] = "16MB"
      begin
        MediaFilter.env_size("NOIR_SPEC_ENV_SIZE_TEST", 1234).should eq(16 * 1024 * 1024)
      ensure
        ENV.delete("NOIR_SPEC_ENV_SIZE_TEST")
      end
    end

    it "falls back to the default on unparsable or non-positive values" do
      ["not-a-size", "0", "-5"].each do |value|
        ENV["NOIR_SPEC_ENV_SIZE_TEST"] = value
        begin
          MediaFilter.env_size("NOIR_SPEC_ENV_SIZE_TEST", 1234).should eq(1234)
        ensure
          ENV.delete("NOIR_SPEC_ENV_SIZE_TEST")
        end
      end
    end
  end
end
