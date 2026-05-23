require "../../spec_helper"
require "../../../src/utils/media_filter"

# NOTE: Predicate methods renamed:
#   is_media_file?   -> media_file?
#   is_file_too_large? -> file_too_large?
# Tests updated accordingly.

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
      temp_file = "/tmp/small_test_file.txt"
      File.write(temp_file, "small content")

      MediaFilter.file_too_large?(temp_file).should be_false

      File.delete(temp_file) if File.exists?(temp_file)
    end

    it "should check file size against custom limit" do
      # Create a temporary file
      temp_file = "/tmp/custom_test_file.txt"
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
      temp_file = "/tmp/large_source_file.cr"
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
      temp_file = "/tmp/size_test_file.txt"
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
end
