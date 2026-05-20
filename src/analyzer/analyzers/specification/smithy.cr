require "../../../models/analyzer"

module Analyzer::Specification
  # Smithy IDL (https://smithy.io) is AWS's interface definition language.
  # HTTP bindings on `operation` shapes (`@http` trait) and member traits
  # (`@httpLabel`, `@httpHeader`, `@httpQuery`, `@httpPayload`) map
  # directly to Noir endpoints, so we parse them shape-by-shape rather
  # than building a full AST.
  class Smithy < Analyzer
    # Parsed representation of one operation's HTTP binding.
    record HttpBinding, method : String, uri : String, code : Int32?

    # Pending traits attached to the next shape or member declaration.
    # `http` is the operation-level `@http(...)` mapping; the others are
    # member-level bindings keyed by the trait name.
    private class PendingTraits
      property http : HttpBinding?
      property? http_label : Bool
      property? http_payload : Bool
      property http_query : String?
      property http_header : String?

      def initialize
        @http = nil
        @http_label = false
        @http_payload = false
        @http_query = nil
        @http_header = nil
      end

      def reset
        @http = nil
        @http_label = false
        @http_payload = false
        @http_query = nil
        @http_header = nil
      end

      def any_member_binding? : Bool
        http_label? || http_payload? || !@http_query.nil? || !@http_header.nil?
      end
    end

    # A field on an `@input` structure with its derived param type.
    record InputMember, name : String, param_type : String

    def analyze
      locator = CodeLocator.instance
      spec_files = locator.all("smithy-spec")

      # Two-pass: first collect every structure's member bindings so an
      # `operation` declared above its input structure still resolves.
      structures = {} of String => Array(InputMember)
      operations = [] of NamedTuple(name: String, file: String, line: Int32, binding: HttpBinding, input: String?)

      spec_files.each do |file|
        begin
          content = File.read(file, encoding: "utf-8", invalid: :skip)
        rescue File::NotFoundError
          @logger.debug "Smithy spec not found during analysis, skipping: #{file}"
          next
        end

        parse_file(content, file, structures, operations)
      end

      operations.each do |op|
        members = op[:input].try { |name| structures[name]? } || [] of InputMember
        params = members.map { |m| Param.new(m.name, "", m.param_type) }

        details = Details.new(PathInfo.new(op[:file], op[:line]))
        endpoint = Endpoint.new(op[:binding].uri, op[:binding].method, params, details)
        @result << endpoint
      end

      @result
    end

    private def parse_file(content : String, file : String,
                           structures : Hash(String, Array(InputMember)),
                           operations : Array(NamedTuple(name: String, file: String, line: Int32, binding: HttpBinding, input: String?)))
      lines = content.lines
      pending = PendingTraits.new
      i = 0
      while i < lines.size
        raw = lines[i]
        line = raw.strip

        if line.empty? || line.starts_with?("//")
          i += 1
          next
        end

        # Trait: starts with `@`. May span multiple lines if it opens
        # a `(` that's not closed on the same line.
        if line.starts_with?('@')
          trait_text, consumed = read_trait(lines, i)
          apply_trait(trait_text, pending)
          i += consumed
          next
        end

        # Shape declaration: keyword + name [ + body ].
        if shape_match = line.match(/^(operation|structure|resource|service|union|enum|intEnum|list|map|string|integer|long|float|double|boolean|blob|timestamp|byte|short|bigDecimal|bigInteger|document)\s+(\w+)/)
          keyword = shape_match[1]
          name = shape_match[2]
          shape_start_line = i + 1

          # Find the opening brace (may be on this or a later line) and
          # capture the body.
          body_start = find_body_start(lines, i)
          if body_start
            body_lines, end_idx = extract_block(lines, body_start)
            case keyword
            when "operation"
              if binding = pending.http
                input_name = parse_operation_input(body_lines)
                operations << {
                  name:    name,
                  file:    file,
                  line:    shape_start_line,
                  binding: binding,
                  input:   input_name,
                }
              end
            when "structure", "union"
              members = parse_structure_members(body_lines)
              structures[name] = members unless members.empty?
            end
            pending.reset
            i = end_idx + 1
            next
          end
        end

        pending.reset
        i += 1
      end
    end

    # Read a trait starting at `lines[idx]`, joining continuation lines
    # until parentheses balance. Returns the joined text and the number
    # of source lines consumed.
    private def read_trait(lines : Array(String), idx : Int32) : Tuple(String, Int32)
      text = lines[idx].strip
      open = text.count('(')
      close = text.count(')')
      consumed = 1
      while open > close && idx + consumed < lines.size
        next_line = lines[idx + consumed].rstrip
        text += " " + next_line.lstrip
        open += next_line.count('(')
        close += next_line.count(')')
        consumed += 1
      end
      {text, consumed}
    end

    private def apply_trait(trait_text : String, pending : PendingTraits)
      # `@http(method: "POST", uri: "/x", code: 201)`
      if trait_text.starts_with?("@http(") || trait_text.starts_with?("@http (")
        method = nil
        uri = nil
        code = nil
        if m = trait_text.match(/method\s*:\s*"([^"]+)"/)
          method = m[1].upcase
        end
        if m = trait_text.match(/uri\s*:\s*"([^"]+)"/)
          uri = m[1]
        end
        if m = trait_text.match(/code\s*:\s*(\d+)/)
          code = m[1].to_i?
        end
        if method && uri
          pending.http = HttpBinding.new(method, uri, code)
        end
        return
      end

      if trait_text == "@httpLabel" || trait_text.starts_with?("@httpLabel ")
        pending.http_label = true
        return
      end

      if trait_text == "@httpPayload" || trait_text.starts_with?("@httpPayload ")
        pending.http_payload = true
        return
      end

      if trait_text.starts_with?("@httpHeader(")
        if m = trait_text.match(/@httpHeader\(\s*"([^"]+)"\s*\)/)
          pending.http_header = m[1]
        end
        return
      end

      if trait_text.starts_with?("@httpQuery(")
        if m = trait_text.match(/@httpQuery\(\s*"([^"]+)"\s*\)/)
          pending.http_query = m[1]
        end
        return
      end
    end

    # Returns the index of the line containing the opening `{` for the
    # shape that starts at `lines[idx]`, or `nil` if the declaration
    # has no body (some Smithy shapes terminate without one).
    private def find_body_start(lines : Array(String), idx : Int32) : Int32?
      j = idx
      while j < lines.size
        return j if lines[j].includes?('{')
        # Stop scanning if a new top-level construct begins before a
        # body shows up.
        if j > idx
          stripped = lines[j].strip
          break if stripped.starts_with?('@') || stripped.match(/^(operation|structure|resource|service|union|enum)\s+/)
        end
        j += 1
      end
      nil
    end

    # Extract the body of a brace-delimited block. Returns the inner
    # lines (without the outer braces) and the source line index of the
    # closing `}`.
    private def extract_block(lines : Array(String), start_idx : Int32) : Tuple(Array(String), Int32)
      body = [] of String
      depth = 0
      started = false
      i = start_idx
      while i < lines.size
        line = lines[i]
        opens = line.count('{')
        closes = line.count('}')

        if !started
          # Find content after the first `{`.
          first_brace = line.index!('{')
          after = line[(first_brace + 1)..]
          depth = opens - closes
          started = true
          if depth == 0
            # Single-line block.
            inner = after.rstrip
            inner = inner[0...inner.rindex!('}')] if inner.includes?('}')
            body << inner unless inner.strip.empty?
            return {body, i}
          else
            body << after unless after.strip.empty?
          end
        else
          depth += opens - closes
          if depth <= 0
            # Trim the closing brace from the final line.
            close_pos = line.rindex('}')
            if close_pos
              prefix = line[0...close_pos]
              body << prefix unless prefix.strip.empty?
            end
            return {body, i}
          end
          body << line
        end

        i += 1
      end
      {body, lines.size - 1}
    end

    # Pull `input: SomeStruct` (or the inline `input := { ... }` form,
    # in which case we return nil because there's no named structure to
    # cross-reference) out of an operation body.
    private def parse_operation_input(body_lines : Array(String)) : String?
      body_lines.each do |line|
        stripped = line.strip
        if m = stripped.match(/^input\s*:\s*(\w+)/)
          return m[1]
        end
      end
      nil
    end

    # Walk a structure body and emit one InputMember per declared field,
    # respecting any member-level `@httpLabel` / `@httpHeader` /
    # `@httpQuery` / `@httpPayload` traits that precede it.
    private def parse_structure_members(body_lines : Array(String)) : Array(InputMember)
      members = [] of InputMember
      pending = PendingTraits.new

      i = 0
      while i < body_lines.size
        line = body_lines[i].strip
        if line.empty? || line.starts_with?("//")
          i += 1
          next
        end

        if line.starts_with?('@')
          trait_text, consumed = read_trait(body_lines, i)
          apply_trait(trait_text, pending)
          i += consumed
          next
        end

        # `name: Type` or `name: Type,` — Smithy 2.0 allows commas as
        # member separators and trailing commas.
        if m = line.match(/^(\w+)\s*:\s*[\w.#]+/)
          member_name = m[1]
          param_type = classify_member(pending)
          # When the trait says `@httpHeader("X-Foo")` /
          # `@httpQuery("foo")`, the wire name wins over the field name.
          wire_name = pending.http_header || pending.http_query || member_name
          members << InputMember.new(wire_name, param_type)
          pending.reset
        else
          pending.reset
        end
        i += 1
      end

      members
    end

    private def classify_member(pending : PendingTraits) : String
      return "path" if pending.http_label?
      return "header" if pending.http_header
      return "query" if pending.http_query
      # `@httpPayload` and unbound members both serialize into the
      # request body; we classify them as JSON.
      "json"
    end
  end
end
