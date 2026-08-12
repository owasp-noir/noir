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
    locator.all_files
  end

  # `{original, expanded}` pairs for every file, expanded once and cached
  # in CodeLocator. The boundary helpers below re-scan the file list once
  # per base path per analyzer; reusing the pre-expanded paths keeps the
  # monorepo cost off the O(bases) multiplier.
  private def all_files_expanded : Array(Tuple(String, String))
    CodeLocator.instance.expanded_file_map
  end

  @walked_path_index : Hash(String, String)? = nil

  # The as-walked spelling of a path an analyzer resolved with
  # `File.expand_path` — a config `<include>` target, a route file named from
  # a source file. `code_paths` are reported the way the walker handed them
  # over, so a resolved path has to be mapped back before it reaches a report:
  # left absolute it puts the scanning machine's directory layout into
  # anything shared, and a SARIF `artifactLocation.uri` that isn't
  # repo-relative can't be matched to a file by GitHub code scanning.
  #
  # Falls back to the input for a file outside the scan — there is nothing
  # better to say about it.
  def walked_path(expanded : String) : String
    index = (@walked_path_index ||= all_files_expanded.each_with_object({} of String => String) do |(file, file_expanded), map|
      map[file_expanded] ||= file
    end)
    index[expanded]? || expanded
  end

  # Get files filtered by path prefix
  #
  # No `File.directory?` guard: the detector's walk only registers a
  # path in `file_map` after `next unless info.file?` (see
  # `detect_techs`), so every entry is already a regular file. The guard
  # was a guaranteed-false `stat(2)` paid once per file per analyzer.
  def get_files_by_prefix(prefix : String) : Array(String)
    # `.dup`: the previous `.select` handed back a fresh array, and
    # `all_files` is CodeLocator's live `file_map`. Callers that
    # `reject!`/`<<` the result must not reach through to it.
    return all_files.dup if prefix.empty?

    root = expanded_root_for(prefix)
    result = [] of String
    all_files_expanded.each do |file, expanded|
      next unless Noir::PathScope.under_normalized_root?(expanded, root)
      result << file
    end
    result
  end

  # Get files filtered by extension (uses cached index for O(1) lookup)
  def get_files_by_extension(extension : String) : Array(String)
    CodeLocator.instance.files_by_extension(extension)
  end

  # Union of files matching any of `extensions`. Prefer this over
  # `parallel_analyze(all_files)` + per-file extension filter: the
  # monorepo `file_map` can be 10–100× larger than the language's
  # source set, and walking it only to `next` on every non-matching
  # path is pure overhead.
  def get_files_by_extensions(extensions : Array(String)) : Array(String)
    case extensions.size
    when 0
      [] of String
    when 1
      get_files_by_extension(extensions[0])
    else
      result = [] of String
      extensions.each { |ext| result.concat(get_files_by_extension(ext)) }
      result
    end
  end

  # Files whose basename is exactly `basename` (uses cached index).
  def get_files_by_basename(basename : String) : Array(String)
    CodeLocator.instance.files_by_basename(basename)
  end

  # Scanned files whose path ends with `relative_path` (a `a/b/c.py`
  # style module-ish suffix), optionally restricted to `root`.
  #
  # The in-memory answer to `Dir.glob("root/**/#{relative_path}")`. The
  # glob form walks every directory under the scan root — including the
  # subtrees the detector pruned — so it costs a full filesystem
  # traversal per call; this narrows by basename first and confirms the
  # remaining path with `ends_with?`.
  #
  # Scope note: this resolves against `file_map`, so it sees exactly the
  # files noir actually scanned. A match the glob would have found under
  # an ignored directory (`node_modules/**/urls.py`) or behind
  # `--exclude-path` is deliberately not returned — resolving to a file
  # the scan excluded would contradict every other analyzer lookup.
  def get_files_by_relative_path(relative_path : String, root : String = "") : Array(String)
    return [] of String if relative_path.empty?

    suffix = relative_path.starts_with?("/") ? relative_path : "/#{relative_path}"
    candidates = get_files_by_basename(File.basename(relative_path))
    return [] of String if candidates.empty?

    result = [] of String
    candidates.each do |path|
      next unless path.ends_with?(suffix) || path == relative_path
      next unless root.empty? || path_under_root?(path, root)
      result << path
    end
    result.uniq!
    result
  end

  # Get files filtered by both prefix and extension.
  #
  # Narrows by extension first (O(1) index hit), then by root. The
  # previous shape scanned the whole `file_map` and paid an
  # `under_normalized_root?` test per file before looking at the
  # extension at all — on a monorepo where the language's source set is
  # a small slice of the tree that is mostly wasted work.
  def get_files_by_prefix_and_extension(prefix : String, extension : String) : Array(String)
    candidates = get_files_by_extension(extension)
    return [] of String if candidates.empty?
    # See `get_files_by_prefix` — the index array is live, so hand back
    # a copy rather than aliasing it.
    return candidates.dup if prefix.empty?

    root = expanded_root_for(prefix)
    locator = CodeLocator.instance
    candidates.select do |file|
      Noir::PathScope.under_normalized_root?(locator.expanded_path_for(file), root)
    end
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
    pairs = all_files_expanded
    base_root = base_path.empty? ? nil : expanded_root_for(base_path)

    # Collect directories that are valid `public/` roots: each is
    # the dirname of an anchor file under base_path, with `public/`
    # appended. Cache once so the per-file filter below is O(1)
    # instead of O(N) on the anchor tree.
    project_public_roots = Set(String).new
    pairs.each do |f, expanded|
      next unless anchors.includes?(File.basename(f))
      next unless base_root.nil? || Noir::PathScope.under_normalized_root?(expanded, base_root)
      project_public_roots << Noir::PathScope.normalize_root(File.join(File.dirname(f), "public"))
    end

    result = [] of String
    pairs.each do |file, expanded|
      next unless base_root.nil? || Noir::PathScope.under_normalized_root?(expanded, base_root)
      next if PUBLIC_FILE_IGNORE.includes?(File.basename(file))
      result << file if project_public_roots.any? { |root| expanded != root && Noir::PathScope.under_normalized_root?(expanded, root) }
    end
    result
  end

  # Helper to get public directories content from anywhere in the project
  def get_public_dir_files(base_path : String, folder : String) : Array(String)
    base_root = base_path.empty? ? nil : expanded_root_for(base_path)

    # Normalize folder path
    normalized_folder = folder.strip

    # Handle different folder specification formats
    public_dir_files = [] of String
    all_files_expanded.each do |file, expanded|
      # Ignore VC/OS placeholder files (never served). No directory
      # guard needed — `file_map` holds regular files only.
      next if PUBLIC_FILE_IGNORE.includes?(File.basename(file))

      # Case 1: Folder is a full path
      match =
        if normalized_folder.includes?("/")
          # If folder is an absolute path like "/var/www/assets"
          if normalized_folder.starts_with?("/")
            Noir::PathScope.under_normalized_root?(expanded, expanded_root_for(normalized_folder))
            # If folder is a relative path from base_path like "assets" or "public/assets"
          else
            combined_root = expanded_root_for("#{base_path}/#{normalized_folder}")
            Noir::PathScope.under_normalized_root?(expanded, combined_root)
          end
          # Case 2: Folder is just a name like "assets"
        else
          # Match files under this configured base that have the folder name
          # as a directory component. `file_map` spans every configured
          # base_path, so this must stay scoped to the base currently being
          # processed.
          (base_root.nil? || Noir::PathScope.under_normalized_root?(expanded, base_root)) && file.includes?("/#{normalized_folder}/")
        end

      public_dir_files << file if match
    end

    public_dir_files
  end

  protected def path_under_root?(path : String, root : String) : Bool
    expanded_under_root?(CodeLocator.instance.expanded_path_for(path), root)
  end

  # `path_under_root?` for a path whose expansion the caller already has.
  #
  # `expanded_path_for` is a Hash lookup keyed on the full path string,
  # so it re-hashes the path on every call. Callers that test one file
  # against several roots (`roots.any? { path_under_root?(file, it) }`)
  # paid that per root; hoisting the expansion out of the inner loop
  # makes it once per file. Semantics are identical — `path_under_root?`
  # is now defined in terms of this.
  protected def expanded_under_root?(expanded_path : String, root : String) : Bool
    return true if root.empty?
    Noir::PathScope.under_normalized_root?(expanded_path, expanded_root_for(root))
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
