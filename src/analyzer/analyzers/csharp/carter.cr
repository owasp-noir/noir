require "../../../models/analyzer"
require "../../../miniparsers/csharp_decl_parser"
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

    # A base-list entry naming `ICarterModule` / `CarterModule`.
    MODULE_BASE_RE = /\bI?CarterModule\b/

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

      Noir::CSharpDeclParser.parse(lexer).types.each do |type|
        next unless type.kind == "class" && type.bases.any?(&.matches?(MODULE_BASE_RE))
        # `public DirectorsModule() : base("/directors")` — Carter's
        # constructor base path. `base()` with no literal leaves it empty.
        prefix = type.constructors.find(&.initializer.== "base").try(&.initializer_args).try(&.first?).try(&.literal) || ""
        # Extraction is scoped to `AddRoutes` bodies so MapGroup prefixes
        # and base paths don't leak between modules declared in one file.
        type.methods.each do |method|
          next unless method.name == "AddRoutes"
          analyze_add_routes_body(file, lines, masked_lines, method.header_end, method.end_line, prefix, include_callee)
        end
      end
    end

    private def analyze_add_routes_body(file : String, lines : Array(String), masked_lines : Array(String),
                                        body_start : Int32, body_end : Int32,
                                        prefix : String, include_callee : Bool)
      body_text = lines[body_start..Math.min(body_end, lines.size - 1)].join('\n')
      group_prefixes = extract_map_group_prefixes(body_text)

      each_map_block(lines, masked_lines, body_start..Math.min(body_end, lines.size - 1), group_prefixes) do |block, idx, chain_prefix|
        extract_endpoints_from_map_block(block, group_prefixes, file, idx + 1,
          lines, masked_lines, include_callee, prefix, chain_prefix).each do |endpoint|
          @result << endpoint
        end
      end
    end
  end
end
