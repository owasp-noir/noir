module Noir
  # Path-boundary helpers shared by the analyzers and engines. Monorepo
  # scans (multiple `-b` base paths) have to answer two questions
  # repeatedly: does a file live *under* a given root, and which configured
  # base does it belong to? Both must respect path boundaries — a plain
  # `String#starts_with?` leaks siblings (`/app` would swallow `/app2`) —
  # so the comparison runs on `File.expand_path`-normalized paths.
  #
  # This logic was copy-pasted across half a dozen call sites (FileHelper,
  # Analyzer, PythonEngine, the Dart helper, the Express router scanner,
  # FastAPI). This module is the single source of truth; a future tweak
  # (Windows separators, symlink handling, …) now lands in one place.
  #
  # Hot loops should normalize the loop-invariant root once via
  # `normalize_root` and compare with `under_normalized_root?` rather than
  # paying for `File.expand_path` of the root per file.
  module PathScope
    extend self

    # Canonical comparison form of a root: expanded, with any trailing
    # separator stripped (except the filesystem root itself).
    def normalize_root(root : String) : String
      expanded = File.expand_path(root)
      expanded == File::SEPARATOR ? expanded : expanded.rstrip('/')
    end

    # True when `path` is `root` or sits beneath it on a path boundary.
    # `root` is expanded/normalized internally; an empty `root` matches
    # everything (mirrors the historical `starts_with?("")`).
    def under_root?(path : String, root : String) : Bool
      return true if root.empty?
      under_normalized_root?(File.expand_path(path), normalize_root(root))
    end

    # Boundary check against an already-expanded path and an
    # already-normalized root. Use this in per-file loops where the root is
    # loop-invariant (normalize it once with `normalize_root`).
    def under_normalized_root?(expanded_path : String, normalized_root : String) : Bool
      return expanded_path.starts_with?(File::SEPARATOR) if normalized_root == File::SEPARATOR
      expanded_path == normalized_root || expanded_path.starts_with?(normalized_root + File::SEPARATOR)
    end

    # The most specific (longest normalized) base in `bases` that contains
    # `path`, or nil if none does. Returns the ORIGINAL base string (not its
    # normalized form) so callers can use it as a stable map key.
    def longest_base(path : String, bases : Enumerable(String)) : String?
      expanded_path = File.expand_path(path)
      best_base = nil
      best_size = -1
      bases.each do |base|
        normalized = normalize_root(base)
        next unless under_normalized_root?(expanded_path, normalized)
        next unless normalized.size > best_size
        best_base = base
        best_size = normalized.size
      end
      best_base
    end

    # Remainder of `path` beneath `base_path`, or the bare basename when
    # `path` is outside `base_path` (or no base given). Backs the
    # Python/Dart test-path conventions, which key off the project-relative
    # path so nested fixture trees don't trip the `tests/`/`test/` filters.
    def relative_under(path : String, base_path : String?) : String
      return File.basename(path) if base_path.nil? || base_path.empty?
      expanded_path = File.expand_path(path)
      normalized = normalize_root(base_path)
      return File.basename(path) unless under_normalized_root?(expanded_path, normalized)
      relative = expanded_path[normalized.size..].lchop(File::SEPARATOR)
      relative.empty? ? File.basename(path) : relative
    end
  end
end
