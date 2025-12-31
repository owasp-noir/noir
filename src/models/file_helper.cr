# This module provides helper methods to retrieve files from CodeLocator
# instead of using Dir.glob, improving efficiency by reusing files already scanned

module FileHelper
  # Get all files from CodeLocator
  def all_files : Array(String)
    locator = CodeLocator.instance
    locator.all("file_map")
  end

  # Get files filtered by path prefix
  def get_files_by_prefix(prefix : String) : Array(String)
    all_files.select { |file| file.starts_with?(prefix) && !File.directory?(file) }
  end

  # Get files filtered by extension
  def get_files_by_extension(extension : String) : Array(String)
    all_files.select { |file| !File.directory?(file) && File.extname(file) == extension }
  end

  # Get files filtered by both prefix and extension
  def get_files_by_prefix_and_extension(prefix : String, extension : String) : Array(String)
    all_files.select { |file| file.starts_with?(prefix) && !File.directory?(file) && File.extname(file) == extension }
  end

  # Get public files (files that should be served as static content)
  # This method searches for any "public" directory within the base_path (at any depth level)
  def get_public_files(base_path : String) : Array(String)
    # Get all files in the project
    files = all_files

    # Filter files that are inside a "public" directory under the base_path
    public_files = files.select do |file|
      # Check if file is under base_path
      file.starts_with?(base_path) &&
        # Check if file contains "/public/" directory component in its path
        file.includes?("/public/") &&
        # Ensure it's not a directory
        !File.directory?(file)
    end

    public_files
  end

  # Helper to populate a channel from file list instead of using Dir.glob
  def populate_channel_with_files(channel : Channel(String))
    files = all_files
    spawn do
      files.each do |file|
        channel.send(file)
      end
      channel.close
    end
  end

  # Helper to get public directories content from anywhere in the project
  def get_public_dir_files(base_path : String, folder : String) : Array(String)
    # Get all files in the project
    files = all_files

    # Normalize folder path
    normalized_folder = folder.strip

    # Handle different folder specification formats
    public_dir_files = files.select do |file|
      # Ignore directories
      next false if File.directory?(file)

      # Case 1: Folder is a full path
      if normalized_folder.includes?("/")
        # If folder is an absolute path like "/var/www/assets"
        if normalized_folder.starts_with?("/")
          file.starts_with?(normalized_folder) && !File.directory?(file)
          # If folder is a relative path from base_path like "assets" or "public/assets"
        else
          combined_path = "#{base_path}/#{normalized_folder}"
          file.starts_with?(combined_path) && !File.directory?(file)
        end
        # Case 2: Folder is just a name like "assets"
      else
        # Match files that have the folder name as a directory component
        file.includes?("/#{normalized_folder}/") && !File.directory?(file)
      end
    end

    public_dir_files
  end
end
