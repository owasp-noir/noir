require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class GraphqlSdl < Detector
    # SDL declaration signals — distinguished at top-level only by
    # `sdl_document?`. A broad keyword-only check is too loose: generated
    # operation documents often select fields named `type`, `schema`, or
    # `enum`, and those field names can appear at the start of an indented line.
    SDL_DECLARATION = /^(?:(?:extend\s+)?(?:type|input|interface|enum|scalar)\s+[A-Za-z_][A-Za-z0-9_]*\b|(?:extend\s+)?union\s+[A-Za-z_][A-Za-z0-9_]*\s*=|directive\s+@[A-Za-z_][A-Za-z0-9_]*\b|(?:extend\s+)?schema\b)/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless sdl_document?(file_contents)

      locator = CodeLocator.instance
      locator.push("graphql-sdl", filename)
      true
    end

    private def sdl_document?(file_contents : String) : Bool
      depth = 0
      in_block_string = false

      file_contents.each_line do |line|
        candidate, in_block_string = detection_line(line, in_block_string)
        if depth == 0 && candidate.strip.match(SDL_DECLARATION)
          return true
        end

        depth = update_depth(candidate, depth)
      end

      false
    end

    private def detection_line(line : String, in_block_string : Bool) : Tuple(String, Bool)
      return {"", true} if in_block_string && !line.includes?("\"\"\"")
      return {"", false} if in_block_string

      if triple_start = line.index("\"\"\"")
        before = line[0...triple_start]
        rest = line[(triple_start + 3)..]
        if rest && rest.includes?("\"\"\"")
          return {before, false}
        end
        return {before, true}
      end

      comment_start = line.index('#')
      return {line[0...comment_start], false} if comment_start
      {line, false}
    end

    private def update_depth(line : String, current : Int32) : Int32
      depth = current
      line.each_char do |char|
        case char
        when '{'
          depth += 1
        when '}'
          depth -= 1 if depth > 0
        end
      end
      depth
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".graphql") ||
        filename.ends_with?(".gql") ||
        filename.ends_with?(".graphqls")
    end

    def set_name
      @name = "graphql_sdl"
    end

    # Registers every SDL path in `CodeLocator` for the analyzer pass.
    # Must keep running after the first match so all schema files get picked up.
    def idempotent? : Bool
      false
    end
  end
end
