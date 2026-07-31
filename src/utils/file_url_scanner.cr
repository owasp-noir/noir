require "./text_file"
require "../models/code_locator"

module Noir
  # Shared line/URL extraction for the `FileAnalyzer` hooks
  # (`file_analyzers/string.cr`, `file_analyzers/base64.cr`).
  #
  # Those hooks are the only analyzers that run against *every* file in the
  # project regardless of detected technology, so both what they accept and
  # what they cost apply to every scan that passes `-u/--url`. Three things
  # are centralised here:
  #
  #   * reading through the detector's content cache instead of re-opening
  #     the file per hook,
  #   * rejecting lines that are binary payload rather than text,
  #   * turning a raw `https?://…` run into a URL, or rejecting it.
  module FileUrlScanner
    # Control characters that never appear in a text line. `\t` (0x09) is
    # legitimate indentation; `\n` / `\r` are consumed by `each_line`. A line
    # carrying any of the rest is binary payload that happens to sit in a
    # file with a text-ish extension — the detector's binary sniff only reads
    # the first 512 bytes, so protobuf/asset blobs with a clean header still
    # reach the analyzers. URL-shaped byte runs inside them are noise.
    BINARY_LINE_RE = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

    # A URL literal, terminated by any character that cannot appear in one.
    # Besides whitespace this stops at the quoting/markup characters that
    # actually wrap URLs in the wild — `"` and `'` (string literals), `<` and
    # `>` (XML/HTML markup and RFC 3986 angle-bracket delimiters), and the
    # RFC 3986 "unwise" set (`\` `^` `` ` `` `|`). Without the markup stop,
    # `<string>https://x/install</string>` yielded the endpoint
    # `https://x/install</string>`.
    #
    # `{` / `}` are deliberately kept: a templated `https://api/x/{id}` is a
    # real endpoint declaration, not markup.
    URL_RE = /https?:\/\/[^\s"'<>\\^`|\x00-\x1F\x7F]+/

    # Request files are parsed properly (method, headers, body, `{{vars}}`)
    # by the `http_file` specification analyzer, so scraping their bare URLs
    # here would only add a duplicate `GET` for every non-GET request.
    REQUEST_FILE_EXTENSIONS = {".http", ".rest"}

    # A run of base64 alphabet characters long enough to hold a URL. The
    # surrounding text can make any substring look like one, so decoding is
    # attempted per token and failures are ignored rather than propagated.
    BASE64_TOKEN_RE = /[A-Za-z0-9+\/]{20,}={0,2}/

    # Trailing sentence/prose punctuation. A URL at the end of a Markdown
    # link, a comment or a sentence carries the delimiter with it
    # (`see https://x/donate/).`), and that delimiter is not part of the URL.
    TRAILING_PUNCTUATION = ".,;:!?"

    # Bracket pairs that may legitimately appear *inside* a URL
    # (`…/wiki/Foo_(bar)`), so only an unbalanced closer is trimmed.
    BRACKET_PAIRS = { {'(', ')'}, {'[', ']'}, {'{', '}'} }

    # Yields each line of `path` with its 0-based index, reading through the
    # detector's content cache when the file is there. The hooks used to
    # `File.open` the same file once each, so a cached file was read from
    # disk twice per scan on top of the detector's own read.
    def self.each_line(path : String, &)
      if cached = CodeLocator.instance.content_for(path)
        cached.each_line.with_index { |line, index| yield line, index }
      else
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line.with_index { |line, index| yield line, index }
        end
      end
    end

    # True when `line` is binary payload rather than source/prose text.
    def self.binary_line?(line : String) : Bool
      line.matches?(BINARY_LINE_RE)
    end

    # Yields every URL found in `text`, already trimmed of prose punctuation.
    # Candidates that trim away to nothing are skipped. Unlike the previous
    # single `String#match`, every URL on a line is reported — a line
    # declaring two endpoints used to contribute only its first.
    def self.each_url(text : String, &)
      text.scan(URL_RE) do |match|
        url = trim(match[0])
        yield url unless url.nil?
      end
    end

    # Strips trailing punctuation and unbalanced brackets from a raw
    # candidate. Returns nil when nothing addressable is left (no authority
    # after the `://`).
    def self.trim(raw : String) : String?
      url = raw
      loop do
        trimmed = trim_once(url)
        break if trimmed == url
        url = trimmed
      end

      scheme_end = url.index("://")
      return if scheme_end.nil? || url.size <= scheme_end + 3
      url
    end

    private def self.trim_once(url : String) : String
      last = url[-1]?
      return url if last.nil?

      return url.rchop if TRAILING_PUNCTUATION.includes?(last)

      BRACKET_PAIRS.each do |opener, closer|
        # An unbalanced bracket at the end belongs to the surrounding text,
        # not the URL: a closer with no opener came from `](url)` markup, an
        # opener with no closer from a byte run that merely ends in one.
        return url.rchop if last == closer && url.count(closer) > url.count(opener)
        return url.rchop if last == opener && url.count(opener) > url.count(closer)
      end
      url
    end
  end
end
