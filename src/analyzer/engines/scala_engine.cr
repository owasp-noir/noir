require "../../models/analyzer"
require "../../miniparsers/scala_callee_extractor"
require "../../minilexers/scala_lexer"

module Analyzer::Scala
  abstract class ScalaEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `.scala` extension filter baked in. Subclasses that need a custom
    # scan shape can override `analyze` and call this helper directly.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".scala"

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

    protected def extract_scala_brace_block_at(lines : Array(String),
                                               start_index : Int32,
                                               opening_brace : Int32) : Tuple(String, Int32)?
      block = extract_scala_brace_block_with_end_at(lines, start_index, opening_brace)
      return unless block

      {block[0], block[1]}
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

    protected def scala_structural_lines(content : String) : Array(String)
      Noir::ScalaLexer.new(content).masked_lines
    end

    # One lexer per file when an analyzer needs BOTH the code and structural
    # views (take `.code_lines` and `.masked_lines` from it) so the file is
    # lexed once rather than twice.
    protected def scala_lexer(content : String) : Noir::ScalaLexer
      Noir::ScalaLexer.new(content)
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
