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
  # Pattern semantics (unchanged from the detector's original inline form):
  #
  #   * a pattern containing `/` matches the file's path *relative to the
  #     scan base*, as a glob (`tests/*`, `**/vendor/**`), as an exact
  #     directory (`src/legacy`), or as a directory prefix (everything
  #     under `src/legacy/`);
  #   * a pattern without `/` matches the basename as a glob (`*.test.js`);
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
      @path_patterns = CASE_INSENSITIVE ? path_patterns.map(&.downcase) : path_patterns
      @basename_patterns = CASE_INSENSITIVE ? basename_patterns.map(&.downcase) : basename_patterns
      @active = !patterns.empty?
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

      unless @basename_patterns.empty?
        basename = File.basename(candidate)
        return true if @basename_patterns.any? { |pat| File.match?(pat, basename) }
      end

      return false if @path_patterns.empty?

      @path_patterns.any? do |pat|
        # `File.match?` handles the glob forms; the equality / prefix
        # checks add plain-directory exclusion so `--exclude-path
        # src/legacy` drops everything under it, not just a file literally
        # named `src/legacy`.
        dir_pat = pat.rstrip('/')
        File.match?(pat, candidate) || candidate == dir_pat || candidate.starts_with?("#{dir_pat}/")
      end
    end
  end
end
