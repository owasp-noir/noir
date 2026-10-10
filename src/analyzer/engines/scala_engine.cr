require "../../models/analyzer"
require "../../miniparsers/scala_callee_extractor"
require "../../minilexers/scala_lexer"

require "./file_scan_engine"

module Analyzer::Scala
  abstract class ScalaEngine < FileScanEngine
    # `.scala` sources from the extension index. Subclasses that need a
    # custom scan shape can override `analyze` and call this helper
    # directly. Paths are detector-registered regular files — no per-path
    # `File.exists?` / `File.directory?`.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".scala")
    end

    # One precompiled `Regex.union` scan (PCRE2 JIT) replaces two separate
    # `String#includes?` scans of the same path -- Crystal's `includes?` is
    # not Boyer-Moore accelerated, so a single regex pass is cheaper than
    # two. Equivalent to the OR-of-substrings it replaces (union escapes
    # each literal).
    SBT_TEST_PATH_RE = Regex.union("/src/test/", "/src/sbt-test/")

    # Scan-base-relative, never absolute: a `src/test/` directory ABOVE
    # the scan base is not this project's test tree.
    protected def sbt_test_path?(path : String) : Bool
      base_relative_path(path).matches?(SBT_TEST_PATH_RE)
    end

    protected def attach_scala_callees(endpoint : Endpoint, callees : Array(Noir::ScalaCalleeExtractor::Entry))
      Noir::ScalaCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_scala_brace_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      block = extract_scala_brace_block_with_end(lines, start_index)
      return unless block

      {block[0], block[1]}
    end

    protected def extract_scala_brace_block_with_end(lines : Array(String), start_index : Int32) : Tuple(String, Int32, Int32)?
      return if start_index >= lines.size

      opening_brace = scala_structural_opening_brace(lines[start_index])
      return unless opening_brace

      extract_scala_brace_block_with_end_at(lines, start_index, opening_brace)
    end

    protected def extract_scala_brace_block_with_end_at(lines : Array(String),
                                                        start_index : Int32,
                                                        opening_brace : Int32) : Tuple(String, Int32, Int32)?
      return if start_index >= lines.size

      body_after_scala_opening_brace(lines, start_index, opening_brace)
    end

    protected def scala_structural_line(line : String) : String
      stripped, _, _ = Noir::ScalaCalleeExtractor.strip_non_code_with_state(line, 0, false)
      stripped
    end

    protected def scala_code_line(line : String) : String
      Noir::ScalaCalleeExtractor.strip_comment_preserving_strings(line)
    end

    # Whole-file masked views (via `Noir::ScalaLexer`). Unlike the per-line
    # `scala_code_line` / `scala_structural_line`, these thread block-comment
    # depth and triple-quote state across the WHOLE file, so route-shaped DSL
    # inside a `"""…"""` string or a multi-line `/* … */` comment no longer
    # leaks as a phantom endpoint. Index 1:1 with `content.lines`; analyzers
    # that split with `content.split('\n')` should guard the last (possibly
    # empty) line with `[i]? || ""`. Build once per file and reuse.
    #
    #   * code view: comments + triple-quote bodies blanked, regular `"…"`
    #     string literals KEPT (Scala routes are string args).
    #   * structural view: all strings/comments blanked, for brace matching.
    protected def scala_code_lines(content : String) : Array(String)
      Noir::ScalaLexer.new(content).code_lines
    end

    # One lexer per file when an analyzer needs BOTH the code and structural
    # views (take `.code_lines` and `.masked_lines` from it) so the file is
    # lexed once rather than twice.
    protected def scala_lexer(content : String) : Noir::ScalaLexer
      Noir::ScalaLexer.new(content)
    end

    # The source with comments, triple-quote bodies and char literals blanked
    # and `"…"` strings kept (the lexer's code view), as one string with every
    # line in place. Read handler bodies from this, not the raw text, so a
    # comment inside `parameter(/* x */ "q")` cannot hide the literal.
    protected def scala_code_text(lexer : Noir::ScalaLexer) : String
      lexer.code.join
    end

    private def scala_structural_opening_brace(line : String) : Int32?
      scala_structural_line(line).index('{')
    end

    private def body_after_scala_opening_brace(lines : Array(String),
                                               opening_index : Int32,
                                               opening_brace : Int32) : Tuple(String, Int32, Int32)
      opening_line = lines[opening_index]
      first_fragment = opening_line[(opening_brace + 1)..]? || ""
      clean_fragment, block_comment_depth, in_multiline_string = Noir::ScalaCalleeExtractor.strip_non_code_with_state(first_fragment, 0, false)
      body_lines = [] of String
      brace_count = 1 + clean_fragment.count('{') - clean_fragment.count('}')

      if brace_count <= 0
        closing_brace = clean_fragment.rindex('}')
        first_fragment = first_fragment[0...closing_brace] if closing_brace
        return {first_fragment, opening_index + 1, opening_index}
      end

      body_lines << first_fragment
      index = opening_index + 1

      while index < lines.size && brace_count > 0
        line = lines[index]
        stripped, block_comment_depth, in_multiline_string = Noir::ScalaCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        next_brace_count = brace_count + stripped.count('{') - stripped.count('}')

        if next_brace_count <= 0
          if line.strip != "}"
            closing_brace = stripped.rindex('}')
            body_lines << (closing_brace ? line[0...closing_brace] : line)
          end
          return {body_lines.join("\n"), opening_index + 1, index}
        end

        body_lines << line
        brace_count = next_brace_count
        index += 1
      end

      {body_lines.join("\n"), opening_index + 1, index}
    end
  end
end
