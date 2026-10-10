require "../../models/analyzer"

require "./file_scan_engine"
require "../../miniparsers/swift_callee_extractor"
require "../../utils/c_comments"

module Analyzer::Swift
  abstract class SwiftEngine < FileScanEngine
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    FUNCTION_SIGNATURE_PATTERN = /\bfunc\s+([A-Za-z_]\w*)\s*\(/

    # `Tests/...` directory + `*Tests.swift` filename: the rigid Swift
    # Package Manager / XCTest conventions for test sources.
    #
    # Both take the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one — SwiftPM's layout is relative to the package,
    # and matching the absolute path made the scan's answer depend on where
    # the package happened to be checked out.
    def self.swift_test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/Tests/")
      File.basename(relative_path).ends_with?("Tests.swift")
    end

    private def swift_test_path?(path : String) : Bool
      SwiftEngine.swift_test_path?(base_relative_path(path))
    end

    # SwiftPM parks resolved dependency sources under `.build/` (and Xcode
    # under `.swiftpm/`). Scanning them pulls every transitive package's
    # routes into the report — pure noise against the project under test.
    def self.swift_vendor_path?(relative_path : String) : Bool
      relative_path.includes?("/.build/") || relative_path.includes?("/.swiftpm/")
    end

    private def swift_vendor_path?(path : String) : Bool
      SwiftEngine.swift_vendor_path?(base_relative_path(path))
    end

    # `.swift` sources from the extension index. Subclasses that need a
    # custom scan shape can override `analyze` and call this helper
    # directly. Paths are detector-registered regular files — no per-path
    # `File.exists?` / `File.directory?`.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".swift")
    end

    # Source lines with comments blanked and strings kept, column-aligned
    # with the raw lines. Read argument text from these: a comment inside
    # `router.group(/* x */ "api")` must not swallow the literal.
    protected def swift_code_lines(content : String) : Array(String)
      Noir::CComments.strip(content, quotes: "\"").lines
    end

    # Route-path composition shared by the Vapor and Hummingbird
    # analyzers (which carried byte-identical copies): prefix and path
    # join with exactly one `/`, a bare or root side yields the other
    # side normalized, and repeated slashes collapse.
    protected def normalized_route_join(prefix : String, path : String) : String
      return normalize_path(path) if prefix.empty? || prefix == "/"
      return normalize_path(prefix) if path.empty? || path == "/"

      "#{normalize_path(prefix).rstrip("/")}/#{path.lstrip("/")}"
    end

    protected def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized.gsub(%r{/+}, "/")
    end

    protected def scan_accepts?(path : String) : Bool
      # Swift Package Manager convention parks tests under
      # `Tests/<TargetName>Tests/`. Real route handlers never
      # live there, but vapor's own repo accounts for ~58
      # phantom endpoints from `Tests/VaporTests/*Tests.swift`
      # files that register routes against an inline test app.
      # XCTest-style `*Tests.swift` filenames carry the same
      # signal — pick them both up.
      return false if swift_test_path?(path)
      !swift_vendor_path?(path)
    end

    # Extract path parameters from the route pattern (e.g., :id, :userID)
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Params read inside a route's trailing closure. `route_index` is the
    # route line itself, so the closure's own `{` is counted and the scan
    # ends where that closure closes (on the route line for a one-liner).
    # Braces are counted on `code_lines` (`strip_code_lines(lines)`, built
    # once per file: stripping here per route was O(line) per route).
    def extract_function_params(lines : Array(String), code_lines : Array(String), route_index : Int32, endpoint : Endpoint)
      brace_count = 0
      seen_opening_brace = false

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      (route_index...[route_index + 1 + LOOKAHEAD_LIMIT, lines.size].min).each do |i|
        line = lines[i]
        code = code_lines[i]

        # Outside the closure a `func` or another route starts unrelated
        # code; inside it, `req.parameters.get(` is a param read.
        if i > route_index && brace_count <= 0
          break if code.matches?(FUNCTION_SIGNATURE_PATTERN) || route_definition?(line)
        end

        brace_count += code.count('{')
        seen_opening_brace = true if brace_count > 0
        brace_count -= code.count('}')

        extract_params_from_line(line, endpoint, existing_path_params)

        break if seen_opening_brace && brace_count <= 0
      end
    end

    private def call_arguments(line : String, args_start : Int32) : Tuple(String, Int32)?
      # `chars` avoids per-index `String#[]`: on non-ASCII lines each direct
      # `line[index]` re-walks from byte 0 to locate the char offset, making
      # this scan O(n^2). Materializing the char array once keeps indexed
      # access O(1) and the whole scan O(n); the single closing slice below
      # (`line[args_start...index]`) is unchanged and still O(n) once.
      chars = line.chars
      depth = 1
      in_string = false
      escaped = false
      quote = '"'
      index = args_start

      while index < chars.size
        char = chars[index]

        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          if depth == 0
            return {line[args_start...index], index}
          end
        end

        index += 1
      end

      nil
    end

    private def prefix_for_receiver(receiver : String, prefix_by_receiver : Hash(String, String)) : String
      receiver.split('.').reverse_each do |part|
        if prefix = prefix_by_receiver[part]?
          return prefix
        end
      end

      ""
    end

    private def named_handler_bodies(lines : Array(String)) : Hash(String, Tuple(String, Int32))
      bodies = {} of String => Tuple(String, Int32)
      block_comment_depth = 0
      in_multiline_string = false

      lines.each_with_index do |line, index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        match = stripped.match(FUNCTION_SIGNATURE_PATTERN)
        next unless match

        handler_name = match[1]
        next if bodies.has_key?(handler_name)

        opening = stripped.index('{')
        if opening
          bodies[handler_name] = body_after_opening_brace(lines, index, opening)
          next
        end

        if location = next_opening_brace(lines, index + 1, block_comment_depth, in_multiline_string)
          opening_index, opening_brace = location
          bodies[handler_name] = body_after_opening_brace(lines, opening_index, opening_brace)
        end
      end

      bodies
    end

    private def next_opening_brace(lines : Array(String),
                                   start_index : Int32,
                                   block_comment_depth : Int32,
                                   in_multiline_string : Bool) : Tuple(Int32, Int32)?
      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          lines[index],
          block_comment_depth,
          in_multiline_string
        )
        if opening = stripped.index('{')
          return {index, opening}
        end

        break if stripped.match(FUNCTION_SIGNATURE_PATTERN)
      end

      nil
    end

    private def body_after_opening_brace(lines : Array(String), opening_index : Int32, opening_brace : Int32) : Tuple(String, Int32)
      route_line = lines[opening_index]
      first_fragment = route_line[(opening_brace + 1)..]? || ""
      clean_fragment, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first_fragment, 0, false)
      body_lines = [] of String
      brace_count = 1 + clean_fragment.count('{') - clean_fragment.count('}')

      if brace_count <= 0
        closing_brace = clean_fragment.rindex('}')
        first_fragment = first_fragment[0...closing_brace] if closing_brace
        return {first_fragment, opening_index + 1}
      end

      body_lines << first_fragment
      index = opening_index + 1

      while index < lines.size && brace_count > 0
        line = lines[index]
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
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
          break
        end

        body_lines << line
        brace_count = next_brace_count
        index += 1
      end

      {body_lines.join("\n"), opening_index + 1}
    end

    # `lines` with comments and `"""` bodies blanked, block-comment state
    # carried across lines. `keep_strings` keeps `"..."` literals so a
    # route's path can still be read from the stripped line.
    protected def strip_code_lines(lines : Array(String), keep_strings : Bool = false) : Array(String)
      block_comment_depth = 0
      in_multiline_string = false
      lines.map do |line|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string,
          keep_strings
        )
        stripped
      end
    end

    private def structural_opening_brace(line : String) : Int32?
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false)
      stripped.index('{')
    end
  end
end
