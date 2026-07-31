require "file"

# UTF-8 text reads for the scan pipeline.
module Noir::TextFile
  # Reads `path` as UTF-8 text, dropping invalid byte sequences.
  #
  # `File.read(path, encoding: "utf-8", invalid: :skip)` routes the whole
  # file through `IO::Decoder` and libiconv even though the requested
  # conversion is UTF-8 to UTF-8. That costs ~4.5x a plain read and
  # allocates ~12x as much (a decode buffer per chunk on top of the
  # result). Source trees are overwhelmingly valid UTF-8 already, so read
  # the bytes straight and only pay for the transcode when they are not.
  #
  # The result is byte-identical either way. On valid input the decode is
  # the identity — it strips no BOM and translates no newlines — and
  # invalid input still goes through the same `invalid: :skip` decode that
  # dropped the bad sequences before. The fallback decodes the bytes
  # already in hand rather than re-reading the file, so a file that
  # changes mid-scan cannot yield a half-and-half result.
  # UTF-16 byte-order marks. Visual Studio and a good deal of Windows
  # tooling still write source as UTF-16 — `.cs`, `.vb`, `.resx`, `.config`,
  # PowerShell `.ps1` — and in UTF-16 every ASCII character carries a NUL
  # byte. Both the detector walk and `MediaFilter` treat an interior NUL as
  # the signature of a binary blob, so such a file was dropped from the scan
  # outright: no detection, no analysis, no warning beyond a debug line. A
  # UTF-16 C# controller contributed exactly zero endpoints.
  #
  # The BOM settles it. Nothing else is guessed at: a NUL-bearing file with
  # no BOM is still treated as binary.
  UTF16_LE_BOM = Bytes[0xFF_u8, 0xFE_u8]
  UTF16_BE_BOM = Bytes[0xFE_u8, 0xFF_u8]

  def self.read(path : String) : String
    content = File.read(path)
    return transcode_utf16(content) if utf16_bom?(content)
    return content if content.valid_encoding?
    decode(content)
  end

  # True when the bytes open with a UTF-16 BOM. A UTF-32LE file opens
  # `FF FE 00 00`, which shares the UTF-16LE prefix — it is excluded here so
  # it keeps falling through to the binary path rather than being decoded as
  # the wrong width.
  def self.utf16_bom?(content : String) : Bool
    bytes = content.to_slice
    return false if bytes.size < 2
    prefix = bytes[0, 2]
    return false if prefix == UTF16_LE_BOM && bytes.size >= 4 && bytes[2] == 0_u8 && bytes[3] == 0_u8
    prefix == UTF16_LE_BOM || prefix == UTF16_BE_BOM
  end

  # Decode UTF-16 to UTF-8. The `"UTF-16"` encoding name (rather than an
  # explicit endianness) is what consumes the BOM instead of leaving it as a
  # leading U+FEFF in the decoded text.
  def self.transcode_utf16(content : String) : String
    io = IO::Memory.new(content.to_slice)
    io.set_encoding("UTF-16", invalid: :skip)
    io.gets_to_end
  rescue
    decode(content)
  end

  # `invalid: :skip` decode of bytes already in memory.
  def self.decode(content : String) : String
    io = IO::Memory.new(content.to_slice)
    io.set_encoding("utf-8", invalid: :skip)
    io.gets_to_end
  end

  # Match options for a subject that came from `read` (or from the
  # detector's content cache, which `read` fills).
  #
  # PCRE2 revalidates its whole subject as UTF-8 on every match call, and
  # on a large file that validation dominates the match — measured at
  # ~3.4x the cost of the match itself. `read` guarantees valid UTF-8, so
  # the re-check is pure overhead. Only pass this for strings that came
  # through `read`, or for slices of one taken at character boundaries.
  MATCH_OPTIONS = Regex::MatchOptions::NO_UTF_CHECK
end
