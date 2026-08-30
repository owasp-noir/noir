require "file"

module MediaFilter
  # Maximum file size for processing (default 10MB). Specification
  # documents have their own budget — see MAX_SPEC_FILE_SIZE below.
  # Can be overridden with the environment variable NOIR_MAX_FILE_SIZE.
  # Supported formats for NOIR_MAX_FILE_SIZE:
  #   * Plain bytes integer (e.g., 5242880)
  #   * Human-readable with unit suffix (K, KB, M, MB, G, GB) e.g., 5MB, 500K, 1G
  # Invalid / unparsable values fall back to the default (10MB).
  MAX_FILE_SIZE = MediaFilter.env_size("NOIR_MAX_FILE_SIZE", 10 * 1024 * 1024)

  # Size budget for specification documents, overridable with
  # NOIR_MAX_SPEC_FILE_SIZE (same value syntax as NOIR_MAX_FILE_SIZE).
  #
  # `MAX_FILE_SIZE` exists to keep images, archives and compiled blobs out
  # of the scan, and 10MB is a sensible ceiling for that. Applying it to
  # API descriptions was collateral damage: those are plain text, they are
  # the highest-value input noir has, and generated ones routinely pass
  # 10MB. NetBox ships a 12.35MB `contrib/openapi.json` describing 308
  # paths, and every one of them was dropped — not because the document
  # was unreadable, but because a filter aimed at image files measured it.
  #
  # The budget still has to be bounded, because the document is read whole,
  # held in the content cache, and parsed into a JSON/YAML tree that peaks
  # at roughly 5x its size in memory. Measured with a release build:
  # NetBox's 12.35MB document costs 0.18s and 81MB peak RSS for the whole
  # scan; a 76MB variant of it (same document, component schemas
  # multiplied, forced through with the override) costs 0.90s and 392MB.
  # 64MB is the ceiling because it keeps one document under a second and a
  # few hundred MB while leaving 5x headroom over the largest generated
  # spec observed in the wild. Past that a `.json` is a data dump, not an
  # API description.
  #
  # Floored at MAX_FILE_SIZE so that raising the general cap past 64MB
  # lifts specification documents with it rather than capping them below
  # everything else. Lowering the general cap does not lower this budget;
  # use NOIR_MAX_SPEC_FILE_SIZE for that.
  MAX_SPEC_FILE_SIZE = {MediaFilter.env_size("NOIR_MAX_SPEC_FILE_SIZE", 64 * 1024 * 1024), MAX_FILE_SIZE}.max

  # Common media file extensions that should be skipped
  MEDIA_EXTENSIONS = [
    # Images
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".svg", ".ico",
    ".psd", ".raw", ".cr2", ".nef", ".orf", ".sr2", ".heic", ".heif",

    # Videos
    ".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".mpg",
    ".mpeg", ".3gp", ".vob", ".rm", ".rmvb", ".asf", ".ogv",

    # Audio
    ".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma", ".m4a", ".ape", ".ac3",
    ".dts", ".opus", ".amr", ".au", ".ra", ".aiff",

    # Archives (can be very large)
    ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".dmg", ".iso",

    # Documents that might be large binary files
    ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",

    # Binary executables and libraries
    ".exe", ".dll", ".so", ".dylib", ".bin", ".app", ".deb", ".rpm",

    # Database files
    ".db", ".sqlite", ".sqlite3", ".mdb", ".accdb",

    # Other binary formats
    ".ttf", ".otf", ".woff", ".woff2", ".eot",
  ]

  # O(1) lookup set materialized from MEDIA_EXTENSIONS. Used on the hot
  # path — every file in the project is checked once.
  MEDIA_EXTENSION_SET = MEDIA_EXTENSIONS.to_set

  # Extensions that carry an API description or a structured document
  # noir reads as one. These get MAX_SPEC_FILE_SIZE instead of the media
  # cap.
  #
  # The list mirrors the file gates of `src/detector/detectors/specification/*`
  # (`grep -h "detector_for" src/detector/detectors/specification/*.cr`)
  # with two deliberate omissions. Binary container formats get no relief:
  # mitmproxy's `.flow` dumps are NUL-bearing blobs the walk drops on
  # content regardless of size. Neither do the source extensions the AWS
  # CDK detector reads (`.ts`, `.js`, `.py`, …) — a 12MB `.js` or `.py` is
  # a bundled or generated artifact, where a 12MB `.json` is usually
  # exactly the document the scan is looking for.
  #
  # The list is by extension rather than by content because a document's
  # own marker (`"openapi"`, `"swagger"`) can sit anywhere in it, and a
  # prefix sniff that misses one is a silent loss again. The cost of being
  # wrong the other way is small: a 32MB `package-lock.json` matches no
  # specification marker, so the walk reads it and drops every spec
  # detector without parsing — 0.08s more than skipping it outright.
  SPEC_DOCUMENT_EXTENSIONS = [
    # Structured document formats: OpenAPI/Swagger, AsyncAPI, OpenRPC,
    # Postman, HAR, k8s/Istio/Envoy/Kong manifests, CloudFormation,
    # Terraform, WSDL and Burp/ZAP exports all arrive as one of these.
    ".json", ".yaml", ".yml", ".xml", ".toml", ".tf",

    # Format-specific extensions.
    ".har", ".raml", ".wsdl", ".smithy", ".tsp", ".proto", ".bru",
    ".graphql", ".gql", ".graphqls", ".http", ".rest",
  ]

  SPEC_DOCUMENT_EXTENSION_SET = SPEC_DOCUMENT_EXTENSIONS.to_set

  # Cache for parsed size strings
  @@size_cache : Hash(String, Int32) = Hash(String, Int32).new

  # Parse size strings like "10MB", "500K", "1G" or raw bytes ("1048576")
  def self.parse_size(str : String) : Int32
    s = str.strip.upcase
    if cached = @@size_cache[s]?
      return cached
    end
    result = begin
      if m = s.match(/^(\d+)([KMG]?B?)$/)
        num = m[1].to_i64
        unit = m[2]
        factor = case unit
                 when "K", "KB" then 1024_i64
                 when "M", "MB" then 1024_i64 * 1024
                 when "G", "GB" then 1024_i64 * 1024 * 1024
                 else                1_i64
                 end
        total = num * factor
        total > Int32::MAX ? Int32::MAX : total.to_i
      else
        val = s.to_i64
        val > Int32::MAX ? Int32::MAX : val.to_i
      end
    rescue
      0
    end
    @@size_cache[s] = result
    result
  end

  # Byte budget read from `name`, falling back to `default` when the
  # variable is unset, unparsable or non-positive.
  #
  # Split out of the constant initializers so both budgets resolve the same
  # way and a spec can exercise the parsing without reloading the module —
  # the constants read ENV once, at first use.
  def self.env_size(name : String, default : Int32) : Int32
    raw = ENV[name]?
    return default if raw.nil?
    parsed = parse_size(raw)
    parsed > 0 ? parsed : default
  rescue
    default
  end

  # Check if a file should be skipped based on extension
  def self.media_file?(file_path : String) : Bool
    extension = File.extname(file_path).downcase
    MEDIA_EXTENSION_SET.includes?(extension)
  end

  # True when the path names a specification document (see
  # SPEC_DOCUMENT_EXTENSIONS), which is read under the larger budget.
  def self.spec_document?(file_path : String) : Bool
    SPEC_DOCUMENT_EXTENSION_SET.includes?(File.extname(file_path).downcase)
  end

  # The size budget that applies to `file_path`.
  def self.max_size_for(file_path : String) : Int32
    max_size_for_extension(File.extname(file_path).downcase)
  end

  private def self.max_size_for_extension(extension : String) : Int32
    SPEC_DOCUMENT_EXTENSION_SET.includes?(extension) ? MAX_SPEC_FILE_SIZE : MAX_FILE_SIZE
  end

  # Check if a file is too large to process. `max_size` defaults to the
  # budget for the file's own kind — pass one only to override it.
  def self.file_too_large?(file_path : String, max_size : Int32? = nil) : Bool
    # Gracefully handle missing or unreadable files
    return false unless File.exists?(file_path)
    begin
      size = File.size(file_path)
      return false unless size
      size > (max_size || max_size_for(file_path))
    rescue
      false
    end
  end

  # Decide whether a file should be skipped and, if so, return the human
  # readable reason in a single pass — avoids re-stat'ing the file just
  # to compose the log message. Returns `nil` when the file should be
  # processed.
  #
  # When the caller has already obtained a `File::Info` (e.g. the
  # detector walker stats each entry with `follow_symlinks: false`), it
  # can be passed as `info` to skip the size stat entirely.
  #
  # `max_size` defaults to the budget for the file's own kind, so the
  # reported ceiling is the one that was actually applied.
  def self.skip_check(file_path : String, max_size : Int32? = nil, info : File::Info? = nil, sniff_binary : Bool = true) : String?
    extension = File.extname(file_path).downcase
    return "media file (#{extension})" if MEDIA_EXTENSION_SET.includes?(extension)

    limit = max_size || max_size_for_extension(extension)

    size = if info
             info.size
           else
             begin
               File.size(file_path)
             rescue
               nil
             end
           end

    if size && size > limit
      size_mb = (size / (1024.0 * 1024.0)).round(2)
      max_mb = (limit / (1024.0 * 1024.0)).round(2)
      return "file too large (#{size_mb}MB > #{max_mb}MB)"
    end

    # Binary-content sniff: text-extension files (.py, .rb, .js, …)
    # that contain NUL bytes or invalid UTF-8 sequences blow up
    # analyzer regexes with `ArgumentError: UTF-8 error: code points
    # greater than 0x10ffff are not defined`. The exception escapes
    # the spawn fiber and appears on stderr as a Crystal stack trace,
    # which is alarming even though it doesn't crash the run.
    #
    # Sample the first 512 bytes — that's enough to spot the NUL-byte
    # signature of binary blobs (object files, packed assets, etc.)
    # without re-reading the whole file content.
    if sniff_binary && binary_content_signature?(file_path)
      return "binary content (file is text-extension but bytes look binary)"
    end

    nil
  end

  # Cheap binary-content sniff. Reads the first 512 bytes and
  # returns true if the buffer contains a NUL byte (`\x00`), which
  # is the canonical "this is binary, not text" marker — text files
  # in any common encoding (UTF-8, UTF-16-with-BOM, Latin-1, etc.)
  # don't contain interior NULs in practice.
  def self.binary_content_signature?(file_path : String) : Bool
    File.open(file_path) do |io|
      buffer = Bytes.new(512)
      bytes_read = io.read(buffer)
      return false if bytes_read == 0
      sample = buffer[0, bytes_read]
      # A UTF-16 BOM means the interior NULs below are the encoding, not a
      # binary blob — in UTF-16 every ASCII character carries one. Visual
      # Studio and much of the Windows toolchain still write source that way,
      # and without this check those files were dropped from the scan
      # entirely. `Noir::TextFile.read` transcodes them.
      return false if utf16_bom?(sample)
      sample.includes?(0_u8)
    end
  rescue
    false
  end

  private def self.utf16_bom?(sample : Bytes) : Bool
    return false if sample.size < 2
    # UTF-32LE opens `FF FE 00 00` and shares the UTF-16LE prefix; leave it
    # on the binary path rather than decode it at the wrong width.
    return false if sample.size >= 4 && sample[0] == 0xFF_u8 && sample[1] == 0xFE_u8 && sample[2] == 0_u8 && sample[3] == 0_u8
    (sample[0] == 0xFF_u8 && sample[1] == 0xFE_u8) || (sample[0] == 0xFE_u8 && sample[1] == 0xFF_u8)
  end

  # Combined check - returns true if file should be skipped. Prefer
  # {skip_check} on hot paths: it returns the reason in the same call
  # so the caller does not re-stat to log.
  def self.should_skip_file?(file_path : String, max_size : Int32? = nil, info : File::Info? = nil, sniff_binary : Bool = true) : Bool
    !skip_check(file_path, max_size, info, sniff_binary).nil?
  end

  # Get a human-readable reason why a file was skipped. Kept for
  # backwards compatibility; new callers should use {skip_check}.
  def self.skip_reason(file_path : String, max_size : Int32? = nil, info : File::Info? = nil, sniff_binary : Bool = true) : String?
    skip_check(file_path, max_size, info, sniff_binary)
  end
end
