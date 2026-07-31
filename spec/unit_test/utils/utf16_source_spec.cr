require "../../spec_helper"
require "../../../src/utils/text_file"
require "../../../src/utils/media_filter"
require "../../../src/models/noir"
require "file_utils"

# Visual Studio and much of the Windows toolchain still write source as
# UTF-16, where every ASCII character carries a NUL byte. The detector walk
# and MediaFilter both read an interior NUL as the signature of a binary blob,
# so those files were dropped from the scan outright — no detection, no
# analysis, and nothing on stdout to say so.
private UTF16_SOURCE = <<-CS
  using Microsoft.AspNetCore.Mvc;

  namespace App.Controllers
  {
      [ApiController]
      [Route("api/[controller]")]
      public class UsersController : ControllerBase
      {
          [HttpGet("GetAll")]
          public IActionResult GetAll() => Ok();
      }
  }
  CS

private def write_utf16(path : String, text : String, big_endian : Bool = false)
  io = IO::Memory.new
  io.write(big_endian ? Bytes[0xFE_u8, 0xFF_u8] : Bytes[0xFF_u8, 0xFE_u8])
  text.each_char do |char|
    code = char.ord
    hi = ((code >> 8) & 0xFF).to_u8
    lo = (code & 0xFF).to_u8
    io.write(big_endian ? Bytes[hi, lo] : Bytes[lo, hi])
  end
  File.write(path, io.to_slice)
end

describe Noir::TextFile do
  it "decodes a UTF-16 LE source file to UTF-8" do
    path = File.tempname("noir-utf16", ".cs")
    begin
      write_utf16(path, UTF16_SOURCE)
      content = Noir::TextFile.read(path)
      content.should contain("public class UsersController")
      # The BOM is consumed, not left as a leading U+FEFF, and no NUL
      # survives — the analyzers' regexes would match nothing otherwise.
      content.starts_with?("using").should be_true
      content.to_slice.includes?(0_u8).should be_false
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "decodes a UTF-16 BE source file to UTF-8" do
    path = File.tempname("noir-utf16be", ".cs")
    begin
      write_utf16(path, UTF16_SOURCE, big_endian: true)
      Noir::TextFile.read(path).should contain("public class UsersController")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "leaves plain UTF-8 untouched" do
    path = File.tempname("noir-utf8", ".cs")
    begin
      File.write(path, UTF16_SOURCE)
      Noir::TextFile.read(path).should eq(UTF16_SOURCE)
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end

describe MediaFilter do
  it "does not call a UTF-16 source file binary" do
    path = File.tempname("noir-utf16-sniff", ".cs")
    begin
      write_utf16(path, UTF16_SOURCE)
      MediaFilter.binary_content_signature?(path).should be_false
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "still calls a NUL-bearing file with no BOM binary" do
    path = File.tempname("noir-blob", ".cs")
    begin
      File.write(path, Bytes[0x7F_u8, 0x45_u8, 0x4C_u8, 0x46_u8, 0x00_u8, 0x01_u8, 0x00_u8])
      MediaFilter.binary_content_signature?(path).should be_true
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end

describe "scanning a UTF-16 project" do
  it "finds endpoints in a UTF-16 controller" do
    root = File.tempname("noir-utf16-scan")

    begin
      FileUtils.mkdir_p(File.join(root, "Controllers"))
      File.write(File.join(root, "MyApp.csproj"), %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>))
      write_utf16(File.join(root, "Controllers", "UsersController.cs"), UTF16_SOURCE)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      runner = NoirRunner.new(options)
      runner.detect
      runner.analyze
      runner.endpoints.map(&.url).should contain("/api/Users/GetAll")
      CodeLocator.instance.clear("file_map")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
