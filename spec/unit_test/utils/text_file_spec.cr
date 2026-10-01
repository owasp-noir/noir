require "../../spec_helper"
require "../../../src/utils/text_file"
require "file_utils"

describe Noir::TextFile do
  # macOS libiconv passes 5-byte sequences and code points above U+10FFFF
  # through an `invalid: :skip` UTF-8 decode untouched. The scan matches
  # `read`'s output with `NO_UTF_CHECK`, so anything it returns must be
  # valid UTF-8 or PCRE2's behaviour is undefined. Both shapes turned up
  # as loose git objects in gitea's test fixtures.
  it "returns valid UTF-8 even where iconv's skip keeps invalid sequences" do
    dir = File.tempname("noir-text-file")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "blob")
      File.write(path, Bytes[0xF8, 0x88, 0x80, 0x80, 0x80, 0x61, 0x62, 0xF4, 0x90, 0x80, 0x80, 0x63, 0xFF, 0x64])

      content = Noir::TextFile.read(path)
      content.valid_encoding?.should be_true
      content.should eq("abcd")
      /zz/.matches?(content).should be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps dropping ordinary invalid bytes the way it always has" do
    dir = File.tempname("noir-text-file")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "latin1.py")
      File.write(path, Bytes[0x23, 0x20, 0xE9, 0x0A, 0x78, 0x20, 0x3D, 0x20, 0x31, 0x0A])
      Noir::TextFile.read(path).should eq("# \nx = 1\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  # A leading UTF-8 BOM decoded to U+FEFF, which broke `^openapi:`-style
  # line-1 markers and made `JSON.parse` reject a BOM'd openapi.json.
  it "drops a leading UTF-8 BOM without moving any line" do
    dir = File.tempname("noir-text-file")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "api.yaml")
      File.write(path, "\uFEFFopenapi: 3.0.0\npaths: {}\n")

      content = Noir::TextFile.read(path)
      content.should eq("openapi: 3.0.0\npaths: {}\n")
      content.lines.size.should eq(2)
      /^openapi:/.matches?(content).should be_true
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "drops a UTF-8 BOM on the invalid-byte decode path too" do
    dir = File.tempname("noir-text-file")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "openapi.json")
      File.write(path, Bytes[0xEF, 0xBB, 0xBF, 0x7B, 0xFF, 0x7D])
      Noir::TextFile.read(path).should eq("{}")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps a BOM-like sequence that is not at the start" do
    dir = File.tempname("noir-text-file")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "mid.txt")
      File.write(path, "a\uFEFFb")
      Noir::TextFile.read(path).should eq("a\uFEFFb")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
