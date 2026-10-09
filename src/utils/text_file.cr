require "file"
require "../ext/string_search"

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
  # the identity — it translates no newlines — and invalid input still goes
  # through the same `invalid: :skip` decode that dropped the bad sequences
  # before. The fallback decodes the bytes already in hand rather than
  # re-reading the file, so a file that changes mid-scan cannot yield a
  # half-and-half result.
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

  # UTF-8 byte-order mark. Windows editors (Notepad, Visual Studio, a good
  # deal of export tooling) still prepend it. Left in place it decodes to a
  # leading U+FEFF, which is invisible but not whitespace: a marker anchored
  # to the start of line 1 (`^openapi:`) no longer matches and `JSON.parse`
  # rejects the first character, so a BOM'd spec document vanished from the
  # scan. It only ever sits before the first character, so dropping it moves
  # no line number.
  UTF8_BOM = Bytes[0xEF_u8, 0xBB_u8, 0xBF_u8]

  #
  # A path that exists but is not a regular file (after following symlinks)
  # reads as empty. Analyzers probe well-known names (`application.properties`,
  # `package.json`) with `File.exists?`, which is true for a FIFO, and opening
  # a FIFO blocks until a writer appears — the scan hung with no output. A
  # missing path still raises, as before.
  def self.read(path : String) : String
    return "" unless File.info(path).file?
    content = File.read(path)
    return transcode_utf16(content) if utf16_bom?(content)
    content = strip_utf8_bom(content)
    return content if content.valid_encoding?
    decode(content)
  end

  # `content` without a leading UTF-8 BOM. Copies only when there is one.
  def self.strip_utf8_bom(content : String) : String
    bytes = content.to_slice
    return content unless bytes.size >= 3 && bytes[0, 3] == UTF8_BOM
    String.new(bytes[3..])
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

  # Decode UTF-16 (after its BOM, which `utf16_bom?` confirmed) to UTF-8.
  # A lone surrogate and an odd trailing byte are dropped.
  #
  # This used to go through iconv with `invalid: :skip`, which on a lone
  # surrogate skips one *byte*: every later code unit was then read across
  # the wrong byte pair, and the rest of the file came out as valid-looking
  # CJK garbage — one stray surrogate in a comment lost every route below it.
  def self.transcode_utf16(content : String) : String
    bytes = content.to_slice
    little = bytes[0, 2] == UTF16_LE_BOM
    units = Slice(Int32).new((bytes.size - 2) // 2) do |i|
      first, second = bytes[2 + 2 * i].to_i32, bytes[3 + 2 * i].to_i32
      little ? (second << 8) | first : (first << 8) | second
    end

    String.build(units.size) do |io|
      i = 0
      while i < units.size
        unit = units[i]
        i += 1
        if !(0xD800 <= unit <= 0xDFFF)
          io << unit.unsafe_chr
        elsif unit <= 0xDBFF && i < units.size && 0xDC00 <= units[i] <= 0xDFFF
          io << (0x10000 + ((unit - 0xD800) << 10) + (units[i] - 0xDC00)).unsafe_chr
          i += 1
        end
      end
    end
  end

  # `invalid: :skip` decode of bytes already in memory.
  #
  # iconv's idea of "invalid" is narrower than UTF-8's: macOS libiconv
  # passes 5- and 6-byte sequences and code points above U+10FFFF
  # straight through, so the "decoded" text could still be invalid. The
  # scan matches file contents with `MATCH_OPTIONS`, which tells PCRE2
  # not to check — on such a subject its behaviour is undefined, and
  # without the flag the match raises instead. Drop whatever the decode
  # left behind, so `read` really does return valid UTF-8.
  def self.decode(content : String) : String
    io = IO::Memory.new(content.to_slice)
    io.set_encoding("utf-8", invalid: :skip)
    ensure_valid(io.gets_to_end)
  end

  private def self.ensure_valid(text : String) : String
    text.valid_encoding? ? text : text.scrub("")
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
