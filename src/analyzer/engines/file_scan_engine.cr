require "../../models/analyzer"

# Base for engines whose scan is "walk the language's source files and
# extract endpoints from each independently". The `analyze` here replaces
# the byte-identical copy each such engine used to carry: a subclass
# supplies the candidate list (`scan_target_files`), an optional per-path
# veto (`scan_accepts?`, inherited from `Analyzer`), and the per-file
# extraction (`analyze_file`).
#
# Engines whose concrete analyzers write their own `analyze` instead of
# implementing `analyze_file` (Ruby, JavaScript) don't inherit from this;
# they keep their `parallel_file_scan` signature and delegate to
# `Analyzer#scan_files` for the shared skeleton.
abstract class FileScanEngine < Analyzer
  def analyze
    parallel_file_scan do |path|
      result.concat(analyze_file(path))
    end
    result
  end

  abstract def analyze_file(path : String) : Array(Endpoint)

  # Candidate files for this engine's scan. Paths are detector-registered
  # regular files — no per-path `File.exists?` / `File.directory?` needed.
  protected abstract def scan_target_files : Array(String)

  # Subclasses that need a custom scan shape override `analyze` and call
  # this directly (e.g. Amber/Kemal run a public-dir post-pass after the
  # file walk).
  protected def parallel_file_scan(&block : String -> Nil) : Nil
    scan_files(scan_target_files, &block)
  end
end
