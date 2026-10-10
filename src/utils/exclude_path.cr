require "file"

module Noir
  # Compiled `--exclude-path` patterns, and the single implementation of
  # what they mean.
  #
  # The option used to be spelled out inline in the detector's walk
  # (`src/detector/detector.cr`), which is the only place that sees every
  # file — so it protected exactly the analyzers that take their file set
  # from `CodeLocator`. The six adapters that enumerate the filesystem
  # themselves (Spring/Quarkus static resources, Dropwizard config, the Go
  # static-dir resolver, the Android/iOS resource walks) never went through
  # it and happily reported files the user had excluded. `Analyzer#excluded_path?`
  # applies this to them, which is only correct as long as both sides agree
  # on what a pattern means — hence one type, used by both.
  #
  # Pattern semantics (as in `.gitignore`, a pattern that matches a
  # directory excludes everything under it):
  #
  #   * a pattern containing `/` is a glob over the path *relative to the
  #     scan base* of the file or any directory above it: `tests/*` and
  #     `src/legacy` both drop `tests/unit/a.js` / `src/legacy/x/y.go`;
  #   * a pattern without `/` is a glob over the name of the file or of any
  #     directory above it: `*.test.js` drops test files, `tests` drops
  #     every `tests/` directory at any depth;
  #   * a leading `./` on a path pattern is dropped, since the path it is
  #     compared against never carries one: `./tests/**` means `tests/**`.
  #     It is dropped *after* the classification above, so `./app.js` stays
  #     a path pattern for the file at the base rather than becoming a
  #     basename pattern for every `app.js`;
  #   * on macOS/Windows the comparison folds case, because their default
  #     filesystems do. Folding on Linux would wrongly drop case-distinct
  #     files that legitimately coexist.
  struct ExcludePath
    # Mirrors the detector's original `exclude_case_insensitive`.
    CASE_INSENSITIVE = {% if flag?(:darwin) || flag?(:windows) %} true {% else %} false {% end %}

    @path_patterns : Array(String)
    @basename_patterns : Array(String)

    # True when the user supplied at least one usable pattern. Callers
    # should check this before computing a relative path per file — with no
    # `--exclude-path` there is nothing to compute it for.
    getter? active : Bool

    # `raw` is the comma-separated option value. Windows-style backslashes
    # are normalized before the `/` classification, so `src\legacy` is
    # treated as a path pattern (and matches) instead of an unmatchable
    # basename.
    def initialize(raw : String)
      patterns = raw.split(",").map(&.strip.gsub('\\', '/')).reject(&.empty?)
      path_patterns, basename_patterns = patterns.partition(&.includes?('/'))
      path_patterns = path_patterns.map { |pat| ExcludePath.strip_dot_slash(pat) }
      @path_patterns = CASE_INSENSITIVE ? path_patterns.map(&.downcase) : path_patterns
      @basename_patterns = CASE_INSENSITIVE ? basename_patterns.map(&.downcase) : basename_patterns
      @active = !patterns.empty?
    end

    # `./tests` → `tests`, `././tests` → `tests`. A pattern that is nothing
    # but `./` is left alone: stripping it would leave an empty pattern.
    def self.strip_dot_slash(pattern : String) : String
      stripped = pattern
      while stripped.starts_with?("./")
        stripped = stripped[2..]
      end
      stripped.empty? ? pattern : stripped
    end

    # `relative_path` is the file's location relative to the scan base that
    # owns it. A leading `/` is accepted (that is the shape
    # `Analyzer#base_relative_path` returns) and ignored, so both callers
    # can hand over their own spelling.
    #
    # Raises `File::BadPatternError` on a malformed glob, which the
    # detector converts into `Noir::InvalidExcludePathError` — a bad
    # pattern must stop the scan rather than silently exclude nothing.
    def excluded?(relative_path : String) : Bool
      return false unless @active

      candidate = relative_path
      {% if flag?(:windows) %} candidate = candidate.gsub('\\', '/') {% end %}
      candidate = candidate.lchop('/')
      candidate = candidate.downcase if CASE_INSENSITIVE

      # Each pattern is tried against the file and every directory above it,
      # so a pattern that names a directory drops everything under it.
      unless @basename_patterns.empty?
        return true if candidate.split('/').any? { |name| @basename_patterns.any? { |pat| File.match?(pat, name) } }
      end

      return false if @path_patterns.empty?

      prefix = candidate
      loop do
        return true if @path_patterns.any? { |pat| File.match?(pat, prefix) || prefix == pat.rstrip('/') }
        slash = prefix.rindex('/') || return false
        prefix = prefix[0, slash]
      end
    end
  end
end
