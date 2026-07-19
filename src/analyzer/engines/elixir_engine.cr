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
      # Fast reject: most body lines have none of the block keywords, so
      # skip strip_comment + the keyword walk entirely.
      return 0 unless line.includes?("do") || line.includes?("fn") || line.includes?("end")

      # Count on a string-and-comment-stripped copy so the keywords
      # `do`/`fn`/`end` appearing inside a literal (`flash(conn, "…the
      # end")`) or a trailing comment don't shift block depth and
      # truncate the enclosing function.
      code = Noir::ElixirCalleeExtractor.strip_comment(line)
      return 0 unless code.includes?("do") || code.includes?("fn") || code.includes?("end")

      # Linear word-boundary walk replaces three PCRE `\b…​\b` scans.
      # A `do` followed by `:` is the keyword-list form (`do: expr`) and
      # must not open a block — same rule as the previous `(?!:)` regex.
      elixir_block_keyword_delta(code)
    end

    # Count `do`/`fn` openers minus `end` closers on an already
    # string-and-comment-stripped line. Word boundaries match PCRE `\b`
    # over `[A-Za-z0-9_]` (so `end!` still counts as `end`).
    private def elixir_block_keyword_delta(code : String) : Int32
      opens = 0
      closes = 0
      i = 0
      size = code.size
      while i < size
        ch = code[i]
        unless ch.ascii_letter?
          i += 1
          next
        end

        # Only consider tokens at a word boundary.
        if i > 0
          prev = code[i - 1]
          if prev.ascii_alphanumeric? || prev == '_'
            i = skip_elixir_word(code, i, size)
            next
          end
        end

        if elixir_keyword_at?(code, i, size, "do")
          after = i + 2
          # Inline `do:` keyword form is not a block opener.
          opens += 1 unless after < size && code[after] == ':'
          i = after
          next
        end

        if elixir_keyword_at?(code, i, size, "fn")
          opens += 1
          i += 2
          next
        end

        if elixir_keyword_at?(code, i, size, "end")
          closes += 1
          i += 3
          next
        end

        i = skip_elixir_word(code, i, size)
      end
      opens - closes
    end

    private def elixir_keyword_at?(code : String, i : Int32, size : Int32, word : String) : Bool
      n = word.size
      return false if i + n > size
      return false unless code[i, n] == word
      after = i + n
      return true if after >= size
      c = code[after]
      !(c.ascii_alphanumeric? || c == '_')
    end

    private def skip_elixir_word(code : String, i : Int32, size : Int32) : Int32
      while i < size
        c = code[i]
        break unless c.ascii_alphanumeric? || c == '_'
        i += 1
      end
      i
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
        # CodeLocator already registered these paths during detection;
        # skip the per-file `File.exists?` syscall. Missing files surface
        # as read errors inside the analyzer and are logged there.
        parallel_analyze(elixir_source_files) do |path|
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
