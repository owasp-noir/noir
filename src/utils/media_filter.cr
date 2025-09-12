require "file"

module MediaFilter
  # Maximum file size for processing (10MB by default)
  MAX_FILE_SIZE = 10 * 1024 * 1024

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
    ".ttf", ".otf", ".woff", ".woff2", ".eot"
  ]

  # Check if a file should be skipped based on extension
  def self.is_media_file?(file_path : String) : Bool
    extension = File.extname(file_path).downcase
    MEDIA_EXTENSIONS.includes?(extension)
  end

  # Check if a file is too large to process
  def self.is_file_too_large?(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : Bool
    return false unless File.exists?(file_path)
    File.size(file_path) > max_size
  end

  # Combined check - returns true if file should be skipped
  def self.should_skip_file?(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : Bool
    is_media_file?(file_path) || is_file_too_large?(file_path, max_size)
  end

  # Get a human-readable reason why a file was skipped
  def self.skip_reason(file_path : String, max_size : Int32 = MAX_FILE_SIZE) : String?
    return nil unless should_skip_file?(file_path, max_size)
    
    if is_media_file?(file_path)
      "media file (#{File.extname(file_path).downcase})"
    elsif is_file_too_large?(file_path, max_size)
      size_mb = (File.size(file_path) / (1024.0 * 1024.0)).round(2)
      max_mb = (max_size / (1024.0 * 1024.0)).round(2)
      "file too large (#{size_mb}MB > #{max_mb}MB)"
    else
      "unknown reason"
    end
  end
end