require "file"

module MediaFilter
  # Maximum file size for processing (default 10MB).
  # Can be overridden with the environment variable NOIR_MAX_FILE_SIZE.
  # Supported formats for NOIR_MAX_FILE_SIZE:
  #   * Plain bytes integer (e.g., 5242880)
  #   * Human-readable with unit suffix (K, KB, M, MB, G, GB) e.g., 5MB, 500K, 1G
  # Invalid / unparsable values fall back to the default (10MB).
  MAX_FILE_SIZE = begin
    if size_str = ENV["NOIR_MAX_FILE_SIZE"]?
      parsed = MediaFilter.parse_size(size_str)
      parsed > 0 ? parsed : 10 * 1024 * 1024
    else
      10 * 1024 * 1024
    end
  rescue
    10 * 1024 * 1024
  end

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

  # Check if a file should be skipped based on extension
  def self.media_file?(file_path : String) : Bool
    extension = File.extname(file_path).downcase
    MEDIA_EXTENSIONS.includes?(extension)
  end

  # Check if a file is too large to process
  def self.file_too_large?(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : Bool
    # Gracefully handle missing or unreadable files
    return false unless File.exists?(file_path)
    begin
      size = File.size(file_path)
      return false unless size
      size > max_size
    rescue
      false
    end
  end

  # Combined check - returns true if file should be skipped
  def self.should_skip_file?(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : Bool
    media_file?(file_path) || file_too_large?(file_path, max_size)
  end

  # Get a human-readable reason why a file was skipped
  def self.skip_reason(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : String?
    return nil unless should_skip_file?(file_path, max_size)

    if media_file?(file_path)
      "media file (#{File.extname(file_path).downcase})"
    elsif file_too_large?(file_path, max_size)
      size_mb = (File.size(file_path) / (1024.0 * 1024.0)).round(2)
      max_mb = (max_size / (1024.0 * 1024.0)).round(2)
      "file too large (#{size_mb}MB > #{max_mb}MB)"
    else
      "unknown reason"
    end
  end
end
