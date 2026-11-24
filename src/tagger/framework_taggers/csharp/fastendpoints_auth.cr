require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "../../../miniparsers/csharp_decl_parser"
require "./aspnet_access"

@[Noir::TaggerFor(key: "fastendpoints_auth", name: "FastEndpoints Auth Tagger", desc: "Identifies FastEndpoints authentication patterns (Roles, Permissions, Policies)", order: 180)]
class FastEndpointsAuthTagger < FrameworkTagger
  ALLOW_ANONYMOUS_PATTERN = /\bAllowAnonymous\s*\(/
  ROLES_PATTERN           = /\bRoles\s*\(/
  PERMISSIONS_PATTERN     = /\bPermissions\s*\(/
  POLICIES_PATTERN        = /\bPolicies\s*\(/
  POLICY_PATTERN          = /\bPolicy\s*\(/
  CLAIMS_PATTERN          = /\bClaims\s*\(/

  def self.target_techs : Array(String)
    ["cs_fastendpoints"]
  end

  # `c.Endpoints.Configurator = ep => ...`: code run on every endpoint.
  CONFIGURATOR = /\bConfigurator\s*=(?![=>])[^;]*/

  @default_policy : String? = nil
  @configurator : String? = nil
  @units = Hash(String, Tuple(Noir::CSharpLexer, Noir::CSharpDecl::Unit)).new

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @default_policy = nil
    @configurator = nil
    collect_files_by_extension(".cs").each do |path|
      content = read_file(path) || next
      next unless content.includes?("DefaultPolicy") || content.includes?("Configurator")
      code = Noir::CComments.strip(content)
      @default_policy ||= AspnetAccess.default_policy_assignment(code)
      @configurator ||= code.match(CONFIGURATOR).try(&.[0].strip)
    end
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      configure_block = extract_configure_block(content)
      next if configure_block.nil?

      if configure_block.matches?(ALLOW_ANONYMOUS_PATTERN)
        return
      end

      # FastEndpoints endpoints are secure by default: without
      # `AllowAnonymous()` they require an authenticated user.
      description = "Protected by FastEndpoints #{describe_guard(configure_block) || "default authorization (no AllowAnonymous)"}"
      requires = own_requires(path_info, content, endpoint.method)
      requires = [Access::Clause.unresolved(description, description, path_info.path)] if requires.empty?
      endpoint.add_tag(Tag.new("auth", description, "fastendpoints_auth", requires: requires))
      return
    end
  end

  # What the endpoint's own class requires: its `Configure()` body, or the
  # attributes of an attribute-configured endpoint, which otherwise is
  # secure by default. The tag above reads the file's first `Configure`,
  # which may be another class's.
  private def own_requires(path_info : PathInfo, content : String, method : String) : Array(Access::Clause)
    path = path_info.path
    lexer, unit = @units[path] ||= begin
      parsed = Noir::CSharpLexer.new(content)
      {parsed, Noir::CSharpDeclParser.parse(parsed)}
    end
    default = AspnetAccess.default_policy(@default_policy)
    type = path_info.line.try { |line| unit.type_at(line - 1) }
    return [Access::Clause.unresolved("the endpoint's class", "the endpoint's class", path, path_info.line)] unless type
    clauses = [] of Access::Clause
    configure = type.members.find { |member| member.kind == :method && member.name == "Configure" && member.params.empty? }
    if configure && (open = configure.body_open || configure.arrow)
      block = lexer.code_source[open..(configure.body_close || configure.finish)]
      source = "#{type.name}.Configure()"
      cnf =
        case anonymous_verb?(block, method)
        when true  then [[Access::Atom.new(:anonymous)]]
        when false then AspnetAccess.fastendpoints(block, default)
        else            [[Access::Atom.new(:unresolved, "AllowAnonymous in #{source}")]]
        end
      clauses.concat(Access.clauses(cnf, source, path, configure.line + 1))
    end
    authorize = false
    type.attributes.each do |attr|
      source = "[#{attr.text}]"
      if attr.name == "Authorize" && !configure
        authorize = true
        clauses.concat(Access.clauses(AspnetAccess.authorize(attr.argument_text, default), source, path, attr.line + 1))
      elsif attr.name.in?("Authorize", "AllowAnonymous")
        clauses << Access::Clause.unresolved(source, source, path, attr.line + 1)
      end
    end
    clauses.concat(Access.clauses(default, "secure by default", path, path_info.line)) if clauses.empty? && !configure && !authorize
    if text = @configurator
      clauses << Access::Clause.unresolved(text, text)
    end
    clauses
  end

  ALLOW_ANONYMOUS_CALL = /\bAllowAnonymous\s*\(([^()]*)\)/

  # Whether `AllowAnonymous(...)` in `block` opens `method`: with no
  # argument it opens every verb, with `Http.X` arguments only those. Nil
  # when its arguments are not literal verbs.
  private def anonymous_verb?(block : String, method : String) : Bool?
    block.scan(ALLOW_ANONYMOUS_CALL) do |call|
      args = call[1].strip
      return true if args.empty?
      verbs = args.split(',').map(&.strip)
      return unless verbs.all?(&.matches?(/\AHttp\.[A-Z]+\z/))
      return true if verbs.includes?("Http.#{method.upcase}")
    end
    false
  end

  private def extract_configure_block(content : String) : String?
    lines = content.lines
    lines.each_with_index do |line, index|
      next unless line.includes?("Configure") && line.includes?("(") && line.includes?(")")
      next unless line.includes?("override") || line.includes?("public") || line.includes?("protected")
      return capture_method_block(lines, index)
    end
    nil
  end

  private def capture_method_block(lines : Array(String), start_index : Int32) : String
    io = String::Builder.new
    brace = 0
    started = false
    index = start_index
    while index < lines.size
      line = lines[index]
      brace += line.count('{') - line.count('}')
      started ||= brace > 0 || line.includes?("{")
      io << line
      io << '\n'
      if started && brace <= 0 && line.includes?("}")
        break
      end
      index += 1
    end
    io.to_s
  end

  private def describe_guard(block : String) : String?
    return "Roles" if block.matches?(ROLES_PATTERN)
    return "Permissions" if block.matches?(PERMISSIONS_PATTERN)
    return "Policies" if block.matches?(POLICIES_PATTERN)
    return "Policy" if block.matches?(POLICY_PATTERN)
    return "Claims" if block.matches?(CLAIMS_PATTERN)
    nil
  end
end
