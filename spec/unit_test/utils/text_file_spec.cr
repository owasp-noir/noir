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
end
