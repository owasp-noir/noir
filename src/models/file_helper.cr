# This module provides helper methods to retrieve files from CodeLocator
# instead of using Dir.glob, improving efficiency by reusing files already scanned
require "../utils/path_scope"

module FileHelper
  # Version-control / OS placeholder files that sit inside `public/`
  # directories (often to keep an otherwise-empty dir in git) but are
  # never served as real endpoints. Matched by exact basename so genuine
  # static files keep flowing through — e.g. `.well-known/dnt-policy.txt`
  # (basename `dnt-policy.txt`) is unaffected.
  PUBLIC_FILE_IGNORE = Set{".gitkeep", ".keep", ".gitignore", ".DS_Store", ".placeholder"}

  # Get all files from CodeLocator
  def all_files : Array(String)
    locator = CodeLocator.instance
    locator.all("file_map")
  end

  # Get files filtered by path prefix
  def get_files_by_prefix(prefix : String) : Array(String)
    all_files.select { |file| path_under_root?(file, prefix) && !File.directory?(file) }
  end

  # Get files filtered by extension (uses cached index for O(1) lookup)
  def get_files_by_extension(extension : String) : Array(String)
    CodeLocator.instance.files_by_extension(extension)
  end

  # Get files filtered by both prefix and extension
  def get_files_by_prefix_and_extension(prefix : String, extension : String) : Array(String)
    all_files.select { |file| path_under_root?(file, prefix) && !File.directory?(file) && File.extname(file) == extension }
  end

  # Get public files (files that should be served as static content)
  #
  # Returns files that are inside a `public/` directory that is the
  # *sibling* of a manifest file (`shard.yml` for Crystal, `Gemfile`
  # for Ruby/Rails). The previous shape matched any `*/public/*`
  # substring under base_path, which had a real false-positive
  # surface: a repo that hosts a Crystal framework fixture alongside
  # an unrelated static site (e.g. a built docs directory at
  # `docs/public/`) would have every file in the docs site surface
  # as a framework endpoint. The previous fix scoped to `shard.yml`
  # only, which broke Rails monorepos like `App/Gemfile` +
  # `App/public/secret.html` — `App/public/*` no longer surfaced
  # because there was no sibling `shard.yml`.
  def get_public_files(base_path : String, anchors : Array(String) = ["shard.yml", "Gemfile"]) : Array(String)
    files = all_files

    # Collect directories that are valid `public/` roots: each is
    # the dirname of an anchor file under base_path, with `public/`
    # appended. Cache once so the per-file filter below is O(1)
    # instead of O(N) on the anchor tree.
    project_public_roots = Set(String).new
    files.each do |f|
      next unless anchors.includes?(File.basename(f))
      next unless path_under_root?(f, base_path)
      project_public_roots << File.join(File.dirname(f), "public")
    end

    files.select do |file|
      next false unless path_under_root?(file, base_path)
      next false if File.directory?(file)
      next false if PUBLIC_FILE_IGNORE.includes?(File.basename(file))
      project_public_roots.any? { |root| file != root && path_under_root?(file, root) }
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
      # Ignore VC/OS placeholder files (never served).
      next false if PUBLIC_FILE_IGNORE.includes?(File.basename(file))

      # Case 1: Folder is a full path
      if normalized_folder.includes?("/")
        # If folder is an absolute path like "/var/www/assets"
        if normalized_folder.starts_with?("/")
          path_under_root?(file, normalized_folder) && !File.directory?(file)
          # If folder is a relative path from base_path like "assets" or "public/assets"
        else
          combined_path = "#{base_path}/#{normalized_folder}"
          path_under_root?(file, combined_path) && !File.directory?(file)
        end
        # Case 2: Folder is just a name like "assets"
      else
        # Match files under this configured base that have the folder name
        # as a directory component. `file_map` spans every configured
        # base_path, so this must stay scoped to the base currently being
        # processed.
        path_under_root?(file, base_path) && file.includes?("/#{normalized_folder}/") && !File.directory?(file)
      end
    end

    public_dir_files
  end

  protected def path_under_root?(path : String, root : String) : Bool
    return true if root.empty?
    Noir::PathScope.under_normalized_root?(File.expand_path(path), expanded_root_for(root))
  end

  # `root` is almost always loop-invariant across a `select`/scan over
  # thousands of files (it's a configured base path or a resolved static
  # dir), so memoise its normalised form instead of re-running
  # `File.expand_path` per file. The distinct-root set is tiny — typically
  # one entry per configured base path.
  private def expanded_root_for(root : String) : String
    cache = (@expanded_root_cache ||= {} of String => String)
    cache[root] ||= Noir::PathScope.normalize_root(root)
  end
end
