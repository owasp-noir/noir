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
  def self.read(path : String) : String
    content = File.read(path)
    return content if content.valid_encoding?
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
