require "../../../models/analyzer"
require "../../../miniparsers/csharp_decl_parser"
require "./common"
require "./minimal_api_support"

module Analyzer::CSharp
  # Wolverine.Http endpoints: `[WolverineGet("/orders/{id}")]` on a method of
  # any class. Route values bind by name, simple types from the query string,
  # and the first other concrete type is the JSON body; every remaining
  # parameter is resolved from the container (IDocumentSession, IMessageBus…).
  class Wolverine < Analyzer
    analyzer_for "cs_wolverine"

    include Common

    ROUTE_ATTR_RE = /\AWolverine(Get|Post|Put|Patch|Delete|Head|Options)\z/
    PLACEHOLDER   = /\{([^{}]+)\}/
    # Loaded from storage by the route id (Marten/EF), or explicitly not the
    # body: never request input of their own.
    NOT_INPUT_ATTRIBUTES = Set{"Entity", "Document", "Aggregate", "ReadAggregate", "WriteAggregate", "NotBody"}

    @dto_fields = {} of String => Array(String)?

    def analyze
      include_callee = callees_needed?
      get_files_by_extension(".cs").each do |file|
        next if Common.csharp_test_path?(base_relative_path(file))
        content = read_file_content(file)
        next unless content.includes?("Wolverine")

        lexer = Noir::CSharpLexer.new(content)
        lines = lexer.code_lines
        masked = lexer.masked_lines
        Noir::CSharpDeclParser.parse(lexer).types.each do |type|
          type.methods.each do |method|
            method.attributes.each do |attr|
              verb = attr.name.match(ROUTE_ATTR_RE).try(&.[1]) || next
              template = attr.positional.first?.try(&.literal) || next
              endpoint = endpoint(file, method.line + 1, verb.upcase, template, method.params)
              if include_callee
                block, start, skip_first = extract_callable_body(lines, masked, method.header_end)
                attach_csharp_callees(endpoint, block, file, start + 1, true, skip_first_line: skip_first)
              end
              @result << endpoint
            end
          end
        end
      end

      @result
    end

    private def endpoint(file : String, line : Int32, verb : String, template : String, params : Array(Noir::CSharpDecl::Parameter)) : Endpoint
      path = "/" + template.lchop('/').gsub(PLACEHOLDER) { "{#{Common.route_placeholder_name($1)}}" }
      endpoint = Endpoint.new(path, verb, Details.new(PathInfo.new(file, line)))
      route_names = Set(String).new
      path.scan(PLACEHOLDER) do |m|
        endpoint.push_param(Param.new(m[1], "", "path"))
        route_names << m[1].downcase
      end

      body_taken = verb == "GET" || verb == "HEAD"
      params.each do |param|
        next if param.attributes.any? { |attr| NOT_INPUT_ATTRIBUTES.includes?(attr.name) }
        binding = param.attributes.find { |attr| Common::BINDING_ATTRIBUTES.has_key?(attr.name) }
        bound = binding.try { |attr| Common::BINDING_ATTRIBUTES[attr.name] }
        next if bound == "service"
        type = param.type
        name = param.name
        next if type.empty? || name.empty?
        name = binding.try(&.args.first?).try(&.literal) || name
        next if bound.nil? && route_names.includes?(name.downcase)

        base = type.rchop('?').rchop("[]").split('.').last
        if bound
          endpoint.push_param(Param.new(name, "", bound))
        elsif MinimalApiSupport::SIMPLE_BINDING_TYPES.includes?(base)
          endpoint.push_param(Param.new(name, "", "query"))
        elsif !body_taken && !Common.csharp_service_type?(type)
          body_taken = true
          (dto_fields(base) || [name]).each { |field| endpoint.push_param(Param.new(field, "", "json")) }
        end
      end

      endpoint
    end

    # Public properties / positional-record members of the request type,
    # nil when it is not declared in the scan.
    private def dto_fields(name : String) : Array(String)?
      return @dto_fields[name] if @dto_fields.has_key?(name)

      decl_re = /\b(?:class|record|struct)\s+(?:class\s+|struct\s+)?#{Regex.escape(name)}\b/
      found = nil
      get_files_by_extension(".cs").each do |file|
        content = read_file_content(file)
        next unless content.matches?(decl_re)

        lexer = Noir::CSharpLexer.new(content)
        fields = [] of String
        if type = Noir::CSharpDeclParser.parse(lexer).types.find(&.name.== name)
          type.params.try &.each { |param| fields << param.name } if type.kind == "record"
          lines = lexer.code_lines
          (type.start_line..type.end_line).each do |k|
            lines[k]?.try { |l| Common::AUTO_PROPERTY_RE.match(l).try { |p| fields << p[1] } }
          end
        end
        found = fields.uniq unless fields.empty?
        break
      end
      @dto_fields[name] = found
    end
  end
end
