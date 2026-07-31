require "../../../models/analyzer"
require "./common"
require "./minimal_api_support"

module Analyzer::CSharp
  # Extracts endpoints from Carter (https://github.com/CarterCommunity/Carter)
  # modules. A Carter module is a class that either implements
  # `ICarterModule` or derives from the `CarterModule` base class, and
  # registers minimal-API routes inside `AddRoutes(IEndpointRouteBuilder)`.
  #
  # `CarterModule` additionally takes a **base path** through its constructor
  # (`public DirectorsModule() : base("/directors")`), which every route in
  # that module hangs off. Modules using that base were previously invisible
  # to this analyzer (it required the literal string `ICarterModule`), so they
  # fell through to `cs_aspnet_core_minimal_api`, which emitted their routes
  # without the base path — `GET /` and `GET /qs` instead of `GET /directors`
  # and `GET /directors/qs`.
  #
  # Route parsing itself is the same job the minimal-API analyzer does, so it
  # runs on the shared `MinimalApiSupport` helpers with the module base path
  # passed in as a prefix. That also brings delegate parameter binding,
  # `MapGroup` composition, method-group handlers and generic
  # `MapPut<T>("/x", …)` registrations to Carter, none of which the previous
  # hand-rolled copy supported.
  #
  # Extraction is scoped to each module's `AddRoutes` body so MapGroup
  # prefixes and base paths don't leak between modules declared in one file.
  class Carter < Analyzer
    analyzer_for "cs_carter"

    include Common
    include MinimalApiSupport

    # `class X : ICarterModule` / `class X : CarterModule` / with generics or
    # extra interfaces in the base list.
    MODULE_CLASS_RE = /\bclass\s+(\w+)(?:\s*<[^>]*>)?\s*:[^{]*\bI?CarterModule\b/

    # `public DirectorsModule() : base("/directors")` — Carter's constructor
    # base path. `base()` with no literal leaves the prefix empty.
    BASE_PATH_RE = /:\s*base\s*\(\s*@?"([^"]*)"/

    ADD_ROUTES_RE = /\bAddRoutes\s*\(/

    def analyze
      include_callee = callees_needed?

      get_files_by_extension(".cs").each do |file|
        next unless File.exists?(file)
        next if Common.csharp_test_path?(base_relative_path(file))

        content = read_file_content(file)
        next unless Common.carter_module_source?(content)

        analyze_carter_file(file, content, include_callee)
      end

      @result
    end

    private def analyze_carter_file(file : String, content : String, include_callee : Bool)
      lexer = Noir::CSharpLexer.new(content)
      # Comment-blanked, string-preserving view: a commented-out
      # `//app.MapPut<Person>("/", …)` must not register a route, but the live
      # route literals still have to be readable.
      lines = lexer.code_lines
      masked_lines = lexer.masked_lines

      each_module(lines, masked_lines) do |prefix, class_start, class_end|
        each_add_routes_body(lines, masked_lines, class_start, class_end) do |body_start, body_end|
          analyze_add_routes_body(file, lines, masked_lines, body_start, body_end, prefix, include_callee)
        end
      end
    end

    # Yields `{base_path, class_body_start, class_body_end}` for every Carter
    # module class in the file. Classes are located by their base list, so a
    # module nested inside a plain holder class (`static class Outer { class
    # HomeModule : ICarterModule { … } }`) is still found.
    private def each_module(lines : Array(String), masked_lines : Array(String), &)
      lines.each_with_index do |line, index|
        next unless (masked_lines[index]? || line).includes?("class")
        next unless line.matches?(MODULE_CLASS_RE)

        class_end = block_end(masked_lines, index)
        prefix = module_base_path(lines, index, class_end)
        yield prefix, index, class_end
      end
    end

    # The constructor base path declared inside the module class body. Only
    # the module's own constructor can carry it, and a `: base("…")` clause
    # appears nowhere else in a Carter module, so the first match within the
    # class body wins.
    private def module_base_path(lines : Array(String), class_start : Int32, class_end : Int32) : String
      (class_start..Math.min(class_end, lines.size - 1)).each do |idx|
        line = lines[idx]
        next unless line.includes?("base")
        if match = BASE_PATH_RE.match(line)
          return match[1]
        end
      end
      ""
    end

    private def each_add_routes_body(lines : Array(String), masked_lines : Array(String),
                                     class_start : Int32, class_end : Int32, &)
      idx = class_start
      limit = Math.min(class_end, lines.size - 1)
      while idx <= limit
        line = lines[idx]
        if line.matches?(ADD_ROUTES_RE) && (line.includes?("public") || line.includes?("void"))
          _, sig_end = build_signature(lines, masked_lines, idx)
          body_end = block_end(masked_lines, sig_end)
          yield sig_end, Math.min(body_end, limit)
          idx = body_end
        end
        idx += 1
      end
    end

    private def analyze_add_routes_body(file : String, lines : Array(String), masked_lines : Array(String),
                                        body_start : Int32, body_end : Int32,
                                        prefix : String, include_callee : Bool)
      body_text = lines[body_start..Math.min(body_end, lines.size - 1)].join('\n')
      group_prefixes = extract_map_group_prefixes(body_text)

      idx = body_start
      while idx <= body_end && idx < lines.size
        line = lines[idx]
        if route_builder_line?(line)
          block = extract_map_block(lines, idx)
          extract_endpoints_from_map_block(block, group_prefixes, file, idx + 1,
            lines, masked_lines, include_callee, prefix).each do |endpoint|
            @result << endpoint
          end
        end
        idx += 1
      end
    end

    # Index of the line closing the brace block that opens at or after
    # `start_index`. Counting runs over the masked twin so a `}` inside a
    # string literal can't close the block early.
    private def block_end(masked_lines : Array(String), start_index : Int32) : Int32
      depth = 0
      started = false
      idx = start_index
      while idx < masked_lines.size
        masked = masked_lines[idx]
        depth += masked.count('{') - masked.count('}')
        started ||= masked.includes?("{")
        return idx if started && depth <= 0
        idx += 1
      end
      masked_lines.size - 1
    end
  end
end
