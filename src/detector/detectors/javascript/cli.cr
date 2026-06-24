require "../../../models/detector"

module Detector::Javascript
  # Detects JavaScript/TypeScript command-line applications: programs using a
  # CLI framework (commander, yargs, cac, meow, minimist, clipanion, oclif,
  # sade, …), the Node `util.parseArgs` builtin, the Deno/Bun argv runtimes,
  # or the canonical `process.argv.slice(2)` parse. Gates the JS CLI
  # analyzer. Bare `process.argv` / `process.env` are too common to qualify.
  class Cli < Detector
    CLI_LIB_IMPORT = /(?:require\s*\(\s*|from\s+)['"](?:commander|yargs(?:\/(?:yargs|helpers))?|cac|meow|minimist|mri|arg|clipanion|@oclif\/(?:core|command)|sade|gluegun)['"]/

    PARSE_ARGS = /\bparseArgs\s*\(\s*\{/
    DENO_ARGS  = /\bDeno\.args\b/
    BUN_ARGV   = /\bBun\.argv\b/
    ARGV_SLICE = /\bprocess\.argv\.slice\s*\(\s*2\s*\)/

    SOURCE_EXTS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      file_contents.matches?(CLI_LIB_IMPORT) ||
        file_contents.matches?(PARSE_ARGS) ||
        file_contents.matches?(DENO_ARGS) ||
        file_contents.matches?(BUN_ARGV) ||
        file_contents.matches?(ARGV_SLICE)
    end

    def applicable?(filename : String) : Bool
      SOURCE_EXTS.any? { |ext| filename.ends_with?(ext) }
    end

    def set_name
      @name = "js_cli"
    end
  end
end
