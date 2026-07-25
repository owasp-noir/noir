require "../../models/analyzer"
require "../../models/code_locator"

module Analyzer::Specification
  # Base for the specification-format analyzers (OpenAPI, Postman, HAR,
  # Terraform, k8s manifests, proxy exports, …).
  #
  # They do not walk the file tree the way the language engines do. The
  # detector recognises a document and pushes its path into `CodeLocator`
  # under a key, and the analyzer later drains that key. Forty-odd
  # analyzers each open-coded the same drain:
  #
  #     locator = CodeLocator.instance
  #     files = locator.all("some-key")
  #     return @result unless files.is_a?(Array(String))
  #     files.each do |path|
  #       next unless File.exists?(path)
  #       begin
  #         ...
  #       rescue e
  #         @logger.debug "..."
  #         @logger.debug_sub e
  #       end
  #     end
  #
  # with just enough variation between copies that some dropped the
  # existence check, some dropped the per-file rescue (letting one
  # malformed document abort every remaining file for that analyzer), and
  # the log wording differed everywhere. `each_spec_file` is that drain,
  # once.
  abstract class SpecificationEngine < Analyzer
    # Yield every registered path for `key`, skipping paths that no longer
    # resolve and containing per-file failures.
    #
    # The `File.exists?` check is load-bearing, not a leftover. Unlike the
    # language engines — whose paths come from the extension index rebuilt
    # per scan — these keys are never cleared at the start of a scan
    # (`detect_techs` clears only `file_map` and the mobile keys, and
    # `clear_all` runs only between the two halves of a `--diff` run). A
    # second scan in the same process therefore still sees the first
    # scan's registrations, and dropping the check would turn stale
    # entries into read errors.
    #
    # Failures are contained per file: a malformed document is logged and
    # skipped so the remaining files for that analyzer still produce
    # endpoints.
    #
    # `sorted` yields in lexical path order. Only pass it where order is part
    # of the format's meaning — Supabase migrations are named
    # `<timestamp>_<name>.sql`, so lexical order is chronological and a column
    # added in one file and dropped in another only comes out right if they
    # are applied in sequence. Registration order is otherwise whatever the
    # concurrent detector walk produced, so relying on it silently would be a
    # bug.
    protected def each_spec_file(key : String, sorted : Bool = false, &block : String -> Nil) : Nil
      # No `is_a?(Array(String))` guard: `CodeLocator#all` is typed to return
      # `Array(String)`, so the copies of that check in the old analyzers were
      # always true and only read as though `all` might hand back something
      # else.
      paths = CodeLocator.instance.all(key)
      paths = paths.sort if sorted

      paths.each do |path|
        next unless File.exists?(path)

        begin
          block.call(path)
        rescue e
          logger.debug "#{self.class} failed to process #{path}"
          logger.debug_sub e
        end
      end
    end

    # `each_spec_file` plus the `Details` almost every caller builds from
    # the path as its first statement.
    protected def each_spec_file_with_details(key : String, &block : String, Details -> Nil) : Nil
      each_spec_file(key) do |path|
        block.call(path, Details.new(PathInfo.new(path)))
      end
    end
  end
end
