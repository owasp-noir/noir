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

  # Get files filtered by extension (uses cached index for O(1) lookup)
  def get_files_by_extension(extension : String) : Array(String)
    CodeLocator.instance.files_by_extension(extension)
  end

  # Get files filtered by both prefix and extension
  def get_files_by_prefix_and_extension(prefix : String, extension : String) : Array(String)
    all_files.select { |file| file.starts_with?(prefix) && !File.directory?(file) && File.extname(file) == extension }
  end

  # Get public files (files that should be served as static content)
  #
  # Returns files that are inside a `public/` directory that is the
  # *sibling* of a `shard.yml` — that's what a Crystal web project
  # layout actually looks like. The previous shape matched any
  # `*/public/*` substring under base_path, which had a real
  # false-positive surface: a repo that hosts a Crystal framework
  # fixture alongside an unrelated static site (e.g. a built docs
  # directory at `docs/public/`) would have every file in the docs
  # site surface as a framework endpoint.
  def get_public_files(base_path : String) : Array(String)
    files = all_files

    # Collect directories that are valid Crystal-project `public/`
    # roots: each is the dirname of a `shard.yml` file under
    # base_path, with `public/` appended. Cache once so the per-
    # file filter below is O(1) instead of O(N) on the shard tree.
    project_public_roots = Set(String).new
    files.each do |f|
      next unless File.basename(f) == "shard.yml"
      next unless f.starts_with?(base_path)
      project_public_roots << File.join(File.dirname(f), "public")
    end

    files.select do |file|
      next false unless file.starts_with?(base_path)
      next false if File.directory?(file)
      project_public_roots.any? { |root| file.starts_with?(root + "/") }
    end
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

  # Helper to populate a channel with only files matching the given extension
  def populate_channel_with_filtered_files(channel : Channel(String), extension : String)
    files = get_files_by_extension(extension)
    spawn do
      files.each do |file|
        channel.send(file)
      end
      channel.close
    end
  end

  # Helper to populate a channel with files matching any of the given extensions
  def populate_channel_with_filtered_files(channel : Channel(String), extensions : Array(String))
    locator = CodeLocator.instance
    files = extensions.flat_map { |ext| locator.files_by_extension(ext) }
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
