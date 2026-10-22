require "../../models/analyzer"
require "../engines/file_scan_engine"

# Template for a new framework adapter (layer L2).
#
# Copy this file to `src/analyzer/analyzers/{language}/{framework}.cr`,
# rename the class, and point it at your language's engine. See AGENTS.md
# §"Analyzer Layering" and
# docs/content/development/analyzer_architecture/ for the full walkthrough.
#
# The three layers, and which one this file is:
#
#   L0  Language Engine     src/analyzer/engines/{lang}_engine.cr
#                           Owns the file set and the walk. Inherit it.
#   L1  Route Extractor     src/miniparsers/{lang}_route_extractor*.cr
#                           Owns parsing. Call it.
#   L2  Framework Adapter   THIS FILE
#                           Owns framework-specific route/param rules.
#
# **Rule**: an adapter receives routes. It does not walk the filesystem and
# it does not parse tokens. If you find yourself reaching for `Dir.glob`,
# `File.open` or `each_line` here, the work belongs in L0 or L1 instead.
#
# `AnalyzerExample` deliberately sits outside the `Analyzer::` namespace so
# the registry sweep in `initialize_analyzers` skips it — which is also why
# it carries no `analyzer_for`. Your real analyzer needs both.
class AnalyzerExample < FileScanEngine
  # Shape A — per-file extraction.
  #
  # `FileScanEngine#analyze` drives the walk and concatenates whatever each
  # call returns. Use this shape unless you need state that spans files.
  def analyze_file(path : String) : Array(Endpoint)
    endpoints = [] of Endpoint

    # `read_file_content` prefers the detector's content cache and falls
    # back to a disk read, so the file the detector already loaded is free.
    content = read_file_content(path)

    # Delegate parsing to the language's route extractor. For example:
    #
    #   Noir::JSRouteExtractor.extract_routes(path, content, @is_debug).each do |endpoint|
    #     endpoints << endpoint
    #   end
    #
    # Then apply only the framework-specific parts here — param mapping,
    # prefix composition, filters.
    _ = content

    endpoints
  end

  # Candidate files for the walk. A real analyzer inherits this from its
  # language engine (`PhpEngine`, `GoEngine`, …) and does not redeclare it;
  # it is spelled out here because this template has no engine above it.
  #
  # Prefer the detector-built extension index over walking the whole
  # `file_map` — these are registered regular files, so no per-path
  # `File.exists?` / `File.directory?` is needed.
  protected def scan_target_files : Array(String)
    get_files_by_extension(".example")
  end

  # Optional per-path veto, evaluated before `analyze_file`.
  #
  # Match on the scan-base-relative path, never the absolute one. A
  # convention filter that looks at the absolute path hands the decision to
  # whatever directory the checkout happens to live in, so the same source
  # tree reports different endpoints depending on where it was cloned.
  protected def scan_accepts?(path : String) : Bool
    !base_relative_path(path).includes?("/tests/")
  end

  # Shape B — custom `analyze`, when you need closure state, a pre-pass or
  # a post-pass. Override `analyze` instead of `analyze_file` and drive the
  # walk yourself with `parallel_file_scan`:
  #
  #   def analyze
  #     scan_for_router_mounts            # pre-pass
  #     parallel_file_scan do |path|
  #       # ... accumulate into `result` and into local state
  #     end
  #     process_static_dirs(result)       # post-pass
  #     result
  #   end
  #
  # `src/analyzer/analyzers/javascript/hono.cr` is the reference for this
  # shape's `analyze` skeleton — but copy only the skeleton. The rest of that
  # file is layers 2 and 3 fused (its own arg splitter, whitespace skipper,
  # offset→line helper and inline regex route tables), which is exactly what
  # the rule above tells you not to write. For the *body* of a thin adapter,
  # copy `src/analyzer/analyzers/javascript/hapi.cr`: 54 lines that call an
  # extractor and map the result onto `Param`s, and nothing else.
  #
  # `src/analyzer/engines/php_engine.cr` is the reference for Shape A.
end
