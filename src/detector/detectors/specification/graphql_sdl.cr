require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class GraphqlSdl < Detector
    # SDL declaration signals — distinguished at top-level only by
    # `sdl_document?`. A broad keyword-only check is too loose: generated
    # operation documents often select fields named `type`, `schema`, or
    # `enum`, and those field names can appear at the start of an indented line.
    #
    # `sdl_document?` walks the document with a small state machine:
    # - tracks brace depth (only outside strings) so keywords inside selections,
    #   fragments, or default values are ignored
    # - skips block strings (""") and regular strings ("...") so that string
    #   literals containing SDL-like keywords, #, or {}/ do not affect detection
    #   or depth (e.g. default values or descriptions with example SDL)
    # - strips # comments only when not inside a string
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
      in_string = false

      file_contents.each_line do |line|
        candidate, in_block_string, in_string = detection_line(line, in_block_string, in_string)
        if depth == 0 && candidate.strip.match(SDL_DECLARATION)
          return true
        end

        depth = update_depth(candidate, depth)
      end

      false
    end

    # Returns the "visible" code portion of the line (strings and comments excised)
    # and the updated string states for the *next* line.
    #
    # The line is materialized into an `Array(Char)` first: indexing a
    # `String` by char position is O(n) on multi-byte input, so a single
    # long unicode-bearing line (e.g. a one-line block-string description
    # with an emoji) would otherwise make this scan quadratic.
    private def detection_line(line : String, in_block_string : Bool, in_string : Bool) : Tuple(String, Bool, Bool)
      chars = line.chars
      size = chars.size
      visible = String::Builder.new
      i = 0
      curr_block = in_block_string
      curr_str = in_string

      while i < size
        if curr_block
          # inside block string: skip until we see closing """
          if i + 2 < size && chars[i] == '"' && chars[i + 1] == '"' && chars[i + 2] == '"'
            curr_block = false
            i += 3
            next
          end
          i += 1
          next
        end

        if curr_str
          # inside regular "string": skip until unescaped closing "
          ch = chars[i]
          if ch == '\\' && i + 1 < size
            i += 2
            next
          end
          if ch == '"'
            curr_str = false
            i += 1
            next
          end
          i += 1
          next
        end

        # not inside any string
        ch = chars[i]
        if ch == '"'
          if i + 2 < size && chars[i + 1] == '"' && chars[i + 2] == '"'
            curr_block = true
            i += 3
            next
          else
            curr_str = true
            i += 1
            next
          end
        end

        if ch == '#'
          # comment: stop here, do not include # or rest of line in visible code
          break
        end

        visible << ch
        i += 1
      end

      {visible.to_s, curr_block, curr_str}
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
