require "../../../models/detector"

module Detector::Javascript
  # Detects JavaScript/TypeScript command-line applications: programs using a
  # CLI framework (commander, yargs, cac, meow, minimist, clipanion, oclif,
  # sade, arg, command-line-args, getopts, citty, …), the Node
  # `util.parseArgs` builtin, the Deno/Bun argv runtimes, or the canonical
  # `process.argv.slice(2)` parse. Gates the JS CLI analyzer. Bare
  # `process.argv` / `process.env` are too common to qualify.
  class Cli < Detector
    detector_for "js_cli"

    CLI_LIB_IMPORT = /(?:require\s*\(\s*|from\s+)['"](?:commander|yargs(?:\/(?:yargs|helpers))?|cac|meow|minimist|mri|arg|clipanion|@oclif\/(?:core|command)|sade|gluegun|command-line-args|getopts|citty)['"]/

    PARSE_ARGS = /\bparseArgs\s*\(\s*\{/
    DENO_ARGS  = /\bDeno\.args\b/
    BUN_ARGV   = /\bBun\.argv\b/
    ARGV_SLICE = /\bprocess\.argv\.slice\s*\(\s*2\s*\)/

    SOURCE_EXTS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      content_matches?(file_contents, CLI_LIB_IMPORT) ||
        content_matches?(file_contents, PARSE_ARGS) ||
        content_matches?(file_contents, DENO_ARGS) ||
        content_matches?(file_contents, BUN_ARGV) ||
        content_matches?(file_contents, ARGV_SLICE)
    end

    def applicable?(filename : String) : Bool
      SOURCE_EXTS.any? { |ext| filename.ends_with?(ext) }
    end
  end
end
