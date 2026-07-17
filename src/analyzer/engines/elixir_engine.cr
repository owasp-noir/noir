require "../../models/analyzer"
require "../../miniparsers/elixir_callee_extractor"

module Analyzer::Elixir
  abstract class ElixirEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    protected def attach_elixir_callees(endpoint : Endpoint, callees : Array(Noir::ElixirCalleeExtractor::Entry))
      Noir::ElixirCalleeExtractor.attach_to(endpoint, callees)
    end

    # How much a single line shifts Elixir block nesting depth. Every
    # block in Elixir closes with `end` and opens with either a `do`
    # block (`def`/`case`/`if`/`for`/`with`/`receive`/`try`/`cond`/…) or
    # an anonymous `fn`. Counting the block keyword *and* its `do`
    # double-counts the opener — `case x do … end` would read as +2/-1 —
    # which is exactly why a controller action wrapping its body in a
    # `case … do` never balanced and got dropped. Count the opener once:
    # a `do` that isn't the inline `do:` keyword form, plus each `fn`,
    # minus each `end`.
    protected def elixir_block_depth_delta(line : String) : Int32
      # Count on a string-and-comment-stripped copy so the keywords
      # `do`/`fn`/`end` appearing inside a literal (`flash(conn, "…the
      # end")`) or a trailing comment don't shift block depth and
      # truncate the enclosing function.
      code = Noir::ElixirCalleeExtractor.strip_comment(line)
      opens = code.scan(/\bdo\b(?!:)/).size + code.scan(/\bfn\b/).size
      closes = code.scan(/\bend\b/).size
      opens - closes
    end

    # ExUnit's filename convention is rigid: every test module sits in
    # a file named `*_test.exs`, and `mix test` ignores anything else.
    # Production code never adopts that name, so the suffix check is
    # safe for every Elixir analyzer (Phoenix/Plug/Bandit).
    def self.test_path?(path : String) : Bool
      File.basename(path).ends_with?("_test.exs")
    end

    protected def elixir_test_path?(path : String) : Bool
      ElixirEngine.test_path?(path)
    end

    # Phoenix uses `.ex` only; Plug also accepts `.exs`. Pull both from
    # the extension index instead of walking the whole `file_map` (which
    # includes every language in a monorepo) and re-filtering inside
    # each analyzer.
    protected def elixir_source_files : Array(String)
      get_files_by_extension(".ex") + get_files_by_extension(".exs")
    end

    # Walk only Elixir sources concurrently. Extension + ExUnit-test
    # filtering lives here so framework adapters don't re-check every
    # path the monorepo file map yields.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(elixir_source_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next if elixir_test_path?(path)

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end
  end
end
