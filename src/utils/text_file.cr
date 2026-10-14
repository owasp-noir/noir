require "file"
require "../ext/string_search"

# UTF-8 text reads for the scan pipeline.
module Noir::TextFile
  # Reads `path` as UTF-8 text; bytes that are not valid UTF-8 are read
  # as Latin-1 (see `decode`).
  #
  # Source trees are overwhelmingly valid UTF-8 already, so read the bytes
  # straight and only pay for `decode` when they are not. The fallback
  # decodes the bytes already in hand rather than re-reading the file, so
  # a file that changes mid-scan cannot yield a half-and-half result.
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
  # A lone surrogate and an odd trailing byte are dropped, and so are any
  # further U+FEFF directly after the BOM (a doubled BOM from concatenating
  # tools); an interior U+FEFF is kept, as on the UTF-8 path.
  #
  # This used to go through iconv with `invalid: :skip`, which on a lone
  # surrogate skips one *byte*: every later code unit was then read across
  # the wrong byte pair, and the rest of the file came out as valid-looking
  # CJK garbage — one stray surrogate in a comment lost every route below it.
  def self.transcode_utf16(content : String) : String
    bytes = content.to_slice
    little = bytes[0, 2] == UTF16_LE_BOM
    count = (bytes.size - 2) // 2
    unit_at = ->(i : Int32) do
      first, second = bytes[2 + 2 * i].to_i32, bytes[3 + 2 * i].to_i32
      little ? (second << 8) | first : (first << 8) | second
    end

    String.build(count) do |io|
      i = 0
      while i < count && unit_at.call(i) == 0xFEFF
        i += 1
      end
      while i < count
        unit = unit_at.call(i)
        i += 1
        if !(0xD800 <= unit <= 0xDFFF)
          io << unit.unsafe_chr
        elsif unit <= 0xDBFF && i < count && 0xDC00 <= (low = unit_at.call(i)) <= 0xDFFF
          io << (0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)).unsafe_chr
          i += 1
        end
      end
    end
  end

  # Decode bytes that are not valid UTF-8: valid sequences are kept and
  # every byte of an invalid one is read as Latin-1 (U+0080–U+00FF).
  #
  # A file with invalid UTF-8 is almost always a legacy single-byte
  # encoding (Latin-1/CP1252 PHP, Java and Python sources), where the
  # `invalid: :skip` decode this replaces turned `/caf\xE9` into `/caf`.
  # Mapping byte-for-byte keeps the character, never shifts a line, and
  # yields valid UTF-8 by construction, which `MATCH_OPTIONS` relies on.
  # Only `read`'s slow path gets here.
  def self.decode(content : String) : String
    String.build(content.bytesize + content.bytesize // 4) do |io|
      reader = Char::Reader.new(content)
      while reader.has_next?
        if byte = reader.error
          io << byte.unsafe_chr
        else
          io << reader.current_char
        end
        reader.next_char
      end
    end
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
