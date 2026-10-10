require "../../../models/analyzer"
require "../../../miniparsers/csharp_type_extractor"
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

    # First in its attribute list or after a comma (`[AllowAnonymous, WolverineGet(...)]`).
    ROUTE_ATTR_RE = /[\[,]\s*(?:Wolverine\.Http\.)?Wolverine(Get|Post|Put|Patch|Delete|Head|Options)(?:Attribute)?\s*\(\s*@?"([^"]*)"/
    PLACEHOLDER   = /\{([^{}]+)\}/
    # Loaded from storage by the route id (Marten/EF), or explicitly not the
    # body: never request input of their own.
    NOT_INPUT_ATTR_RE = /\[\s*(?:Entity|Document|Aggregate|ReadAggregate|WriteAggregate|NotBody)\b/

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
        lines.each_with_index do |line, i|
          attr = ROUTE_ATTR_RE.match(line) || next
          # The method follows its attribute lists (which may span lines), or
          # shares the line with the last one.
          j = i
          depth = 0
          while j < masked.size
            stripped = masked[j].strip
            break if depth == 0 && !stripped.starts_with?('[')
            depth += stripped.count('[') - stripped.count(']')
            break if depth <= 0 && !stripped.ends_with?(']')
            j += 1
          end
          signature, sig_end = build_signature(lines, masked, j)
          endpoint = endpoint(file, j + 1, attr[1].upcase, attr[2], extract_balanced_param_list(signature) || "")
          if include_callee
            block, start, skip_first = extract_callable_body(lines, masked, sig_end)
            attach_csharp_callees(endpoint, block, file, start + 1, true, skip_first_line: skip_first)
          end
          @result << endpoint
        end
      end

      @result
    end

    private def endpoint(file : String, line : Int32, verb : String, template : String, param_list : String) : Endpoint
      path = "/" + template.lchop('/').gsub(PLACEHOLDER) { "{#{Common.route_placeholder_name($1)}}" }
      endpoint = Endpoint.new(path, verb, Details.new(PathInfo.new(file, line)))
      route_names = Set(String).new
      path.scan(PLACEHOLDER) do |m|
        endpoint.push_param(Param.new(m[1], "", "path"))
        route_names << m[1].downcase
      end

      body_taken = verb == "GET" || verb == "HEAD"
      split_csharp_parameters(param_list).each do |param_def|
        next if param_def.matches?(NOT_INPUT_ATTR_RE)
        bound = Common.binding_attribute_type(param_def)
        next if bound == "service"
        decl = param_def.gsub(/\[[^\]]*\]/, "").sub(/=.*/m, "").gsub(/\b(?:ref|out|in|params)\s+/, "").strip
        type, _, name = decl.rpartition(/\s+/)
        next if type.empty? || name.empty?
        name = Common.explicit_binding_name(param_def) || name
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
      positional_re = /\brecord\s+(?:class\s+|struct\s+)?#{Regex.escape(name)}\s*\(([^)]*)\)/
      found = nil
      get_files_by_extension(".cs").each do |file|
        content = read_file_content(file)
        next unless content.matches?(decl_re)

        lexer = Noir::CSharpLexer.new(content)
        fields = [] of String
        if m = positional_re.match(lexer.code_source)
          split_csharp_parameters(m[1]).each do |arg|
            arg.gsub(/\[[^\]]*\]/, "").split('=').first.strip.split(/\s+/).last?.try { |field| fields << field }
          end
        end
        if type = Noir::CSharpTypeExtractor.extract(lexer).find(&.name.== name)
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
