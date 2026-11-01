require "./csharp_type_extractor"

module Noir
  # Route templates and HTTP verbs that a project's own attribute classes
  # contribute, read from the attribute's definition instead of from a name:
  #
  #   [V3ApiController("series")]  ->  api/v3/series
  #   [RestGetById]                ->  GET {id:int}
  #   [RestPutById]                ->  PUT {id:int?}
  #
  # An attribute is followed through its constructor (`: base(3, resource)`),
  # the `Template` it assigns or returns (`$"api/v{version}/{resource}"`), the
  # `HttpMethods` it lists and the built-in `Http<Verb>Attribute` / `Route`
  # it derives, with the usage's arguments bound to the constructor
  # parameters. Pure text in, no file access: the caller hands it lexed files.
  class CSharpAttributeRoutes
    BUILTIN_VERBS = {
      "HttpGet" => "GET", "HttpPost" => "POST", "HttpPut" => "PUT", "HttpDelete" => "DELETE",
      "HttpPatch" => "PATCH", "HttpHead" => "HEAD", "HttpOptions" => "OPTIONS",
    }
    MAX_DEPTH = 6

    record Result, verb : String?, template : String?
    record Ctor, params : Array(Tuple(String, String?)), base_args : Array(CSharpDecl::Arg)?
    record Decl, base : String?, ctors : Array(Ctor), template : String?, verb : String?, consts : Hash(String, String), scope : String, provider : Bool

    # `Template = $"api/{x}";` in a constructor body.
    TEMPLATE_ASSIGN_RE = /\bTemplate\s*=(?![=>])\s*([^;]+);/
    LITERAL_WORD_RE    = /"(\w+)"/
    PROVIDERS          = {"IRouteTemplateProvider", "IActionHttpMethodProvider"}

    def initialize
      @decls = Hash(String, Array(Decl)).new
    end

    def empty? : Bool
      @decls.empty?
    end

    # Records `type` when it is an attribute class (`FooAttribute`).
    def add(lexer : CSharpLexer, type : CSharpType, scope : String = "") : Nil
      return unless type.name.ends_with?("Attribute")
      decl = type.decl
      # A route-bearing attribute implements the provider interface or derives
      # another attribute class; a plain `: Attribute` with a `Template`
      # property is some other feature's.
      provider = decl.bases.any? { |base| PROVIDERS.includes?(CSharpDecl.simple_name(base)) }
      return unless provider || (type.base_name && type.base_name != "Attribute")
      ctors = decl.constructors.map do |ctor|
        Ctor.new(ctor.params.map { |param| {param.name, param.default} }, ctor.initializer == "base" ? ctor.initializer_args : nil)
      end
      properties = decl.members.select(&.kind.== :property)
      template = properties.find(&.name.== "Template").try(&.value) ||
                 decl.constructors.compact_map { |ctor| body_text(lexer, ctor).try(&.match(TEMPLATE_ASSIGN_RE)).try(&.[1].strip) }.first?
      verb = properties.find(&.name.== "HttpMethods").try(&.value).try(&.match(LITERAL_WORD_RE)).try(&.[1].upcase)
      consts = Hash(String, String).new
      decl.members.each do |member|
        value = member.value
        consts[member.name] = value if value && member.kind == :field && member.modifiers.includes?("const")
      end
      (@decls[type.name.rchop("Attribute")] ||= [] of Decl) << Decl.new(
        type.base_name.try(&.rchop("Attribute")), ctors, template, verb, consts, scope, provider
      )
    end

    private def body_text(lexer : CSharpLexer, member : CSharpDecl::Member) : String?
      open = member.body_open || return
      close = member.body_close || return
      lexer.code_source[open..close]
    end

    # Names of the recorded attributes whose definition reaches a route or
    # verb provider; what one means at a usage (a prefix, a verb, nothing
    # readable) is up to `resolve`.
    def route_names : Array(String)
      @decls.keys.select { |name| @decls[name].any? { |decl| provider?(decl) } }
    end

    # What the usage `attribute` means. `scope` is the project of the file
    # using it: a name two projects both define resolves to the one in the
    # usage's own project, and to nothing when that does not settle it.
    def resolve(attribute : CSharpDecl::Attribute, scope : String = "") : Result?
      positional, named = bind(attribute.args, {} of String => String?, nil)
      resolve_values(attribute.name, positional, named, 0, scope)
    end

    # Positional and `name:` arguments as string values; `Prop = value`
    # arguments set a property of the attribute and bind nothing.
    private def bind(args : Array(CSharpDecl::Arg), env : Hash(String, String?), decl : Decl?) : Tuple(Array(String?), Hash(String, String?))
      positional = [] of String?
      named = Hash(String, String?).new
      args.each do |arg|
        next if arg.property
        if key = arg.name
          named[key] = string_value(arg.text, env, decl)
        else
          positional << string_value(arg.text, env, decl)
        end
      end
      {positional, named}
    end

    private def resolve_values(name : String, args : Array(String?), named : Hash(String, String?), depth : Int32, scope : String) : Result?
      key = name.rchop("Attribute")
      if verb = BUILTIN_VERBS[key]?
        return Result.new(verb, args.first?)
      end
      return Result.new(nil, args.first?) if key == "Route"
      return if depth > MAX_DEPTH
      decl = lookup(key, scope) || return
      resolve_decl(decl, args, named, depth)
    end

    private def lookup(key : String, scope : String) : Decl?
      found = @decls[key]? || return
      return found.first if found.size == 1
      same = found.select { |decl| decl.scope == scope }
      same.first if same.size == 1
    end

    # Whether the chain of `decl` reaches a route/verb provider: a header
    # naming the provider interface, or a built-in `Http<Verb>`/`Route` base.
    private def provider?(decl : Decl, depth = 0) : Bool
      return true if decl.provider
      base = decl.base || return false
      return true if BUILTIN_VERBS.has_key?(base) || base == "Route"
      return false if depth > MAX_DEPTH
      lookup(base, decl.scope).try { |parent| provider?(parent, depth + 1) } || false
    end

    private def resolve_decl(decl : Decl, args : Array(String?), named : Hash(String, String?), depth : Int32) : Result?
      return if depth > MAX_DEPTH || !provider?(decl)
      ctor = decl.ctors.find { |candidate| candidate.params.size >= args.size } || decl.ctors.first?
      env = Hash(String, String?).new
      if ctor
        ctor.params.each_with_index do |(pname, default), index|
          # A supplied argument the scan cannot read stays unread: falling
          # back to the default would name a route the code does not.
          env[pname] = if index < args.size
                         args[index]
                       elsif named.has_key?(pname)
                         named[pname]
                       else
                         default.try { |expr| string_value(expr, env, decl) }
                       end
        end
      end

      inherited = nil
      if base = decl.base
        positional, base_named = bind(ctor.try(&.base_args) || [] of CSharpDecl::Arg, env, decl)
        inherited = resolve_values(base, positional, base_named, depth + 1, decl.scope)
      end

      own = decl.template
      template = own ? string_value(own, env, decl) : inherited.try(&.template)
      verb = decl.verb || inherited.try(&.verb)
      return if verb.nil? && template.nil? && inherited.nil? && own.nil?
      Result.new(verb, template)
    end

    # The text of a string expression: a literal, an interpolation over bound
    # parameters, a bound parameter or a `const` of the class.
    private def string_value(expr : String, env : Hash(String, String?), decl : Decl?, depth = 0) : String?
      expr = expr.strip
      return if depth > MAX_DEPTH
      if expr.matches?(/\A\d+\z/)
        expr
      elsif literal = CSharpDecl.literal(expr)
        literal
      elsif m = expr.match(/\A\$@?"(.*)"\z/m)
        interpolate(m[1], env, decl, depth)
      elsif expr.matches?(/\A[A-Za-z_]\w*\z/)
        if env.has_key?(expr)
          env[expr]
        elsif constant = decl.try(&.consts[expr]?)
          string_value(constant, env, decl, depth + 1)
        end
      end
    end

    private def interpolate(body : String, env : Hash(String, String?), decl : Decl?, depth : Int32) : String?
      failed = false
      value = body.gsub(/\{\{|\}\}|\{([A-Za-z_]\w*)(?::[^}]*)?\}/) do |hole, match|
        next hole[0].to_s if hole == "{{" || hole == "}}"
        resolved = string_value(match[1], env, decl, depth + 1)
        failed = true if resolved.nil?
        resolved || ""
      end
      failed ? nil : value
    end
  end
end
