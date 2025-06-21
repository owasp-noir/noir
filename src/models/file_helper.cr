# This module provides helper methods to retrieve files from CodeLocator
# instead of using Dir.glob, improving efficiency by reusing files already scanned

module FileHelper
  # Get all files from CodeLocator
  def get_all_files : Array(String)
    locator = CodeLocator.instance
    locator.all("file_map")
  end

  # Get files filtered by path prefix
  def get_files_by_prefix(prefix : String) : Array(String)
    get_all_files.select { |file| file.starts_with?(prefix) && !File.directory?(file) }
  end

  # Get files filtered by extension
  def get_files_by_extension(extension : String) : Array(String)
    get_all_files.select { |file| !File.directory?(file) && File.extname(file) == extension }
  end

  # Get files filtered by both prefix and extension
  def get_files_by_prefix_and_extension(prefix : String, extension : String) : Array(String)
    get_all_files.select { |file| file.starts_with?(prefix) && !File.directory?(file) && File.extname(file) == extension }
  end

  # Get public files (files that should be served as static content)
  def get_public_files(base_path : String) : Array(String)
    prefix = "#{base_path}/public/"
    get_files_by_prefix(prefix)
  end

  # Helper to populate a channel from file list instead of using Dir.glob
  def populate_channel_with_files(channel : Channel(String))
    files = get_all_files
    spawn do
      files.each do |file|
        channel.send(file)
      end
      channel.close
    end
  end

  # Helper to get public directories content
  def get_public_dir_files(base_path : String, folder : String) : Array(String)
    prefix = "#{base_path}/#{folder}/"
    get_files_by_prefix(prefix)
  end
end
