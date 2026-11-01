require "../minilexers/csharp_lexer"
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
    record Ctor, params : Array(Tuple(String, String?)), base_args : Array(String)?
    record Decl, base : String?, ctors : Array(Ctor), template : String?, verb : String?, consts : Hash(String, String)

    TEMPLATE_ARROW_RE  = /\bTemplate\s*=>\s*([^;]+);/
    TEMPLATE_ASSIGN_RE = /\bTemplate\s*=(?![=>])\s*([^;]+);/
    HTTP_METHODS_RE    = /\bHttpMethods\s*=>\s*new\s*(?:string)?\s*\[\s*\]\s*\{\s*"(\w+)"/
    CONST_RE           = /\bconst\s+(?:string|int)\s+(\w+)\s*=\s*([^;]+);/
    NAMED_ARG_RE       = /\A(\w+)\s*:(?!:)\s*(.+)\z/m

    def initialize
      @decls = Hash(String, Decl).new
    end

    def empty? : Bool
      @decls.empty?
    end

    # Records `type` when it is an attribute class (`FooAttribute`).
    def add(lexer : CSharpLexer, type : CSharpType) : Nil
      return unless type.name.ends_with?("Attribute")
      # A route-bearing attribute implements the provider interface or derives
      # another attribute class; a plain `: Attribute` with a `Template`
      # property is some other feature's.
      return unless type.header.matches?(/IRouteTemplateProvider|IActionHttpMethodProvider/) || (type.base_name && type.base_name != "Attribute")
      name = type.name.rchop("Attribute")
      last = Math.min(type.end_line, lexer.code_lines.size - 1)
      body = lexer.code_lines[type.start_line..last].join('\n')
      @decls[name] = Decl.new(
        type.base_name.try(&.rchop("Attribute")), constructors(body, type.name),
        (body.match(TEMPLATE_ARROW_RE) || body.match(TEMPLATE_ASSIGN_RE)).try(&.[1].strip),
        body.match(HTTP_METHODS_RE).try(&.[1].upcase), constants(body)
      )
    end

    # Names of the recorded attributes that carry a route (any usage with no
    # arguments), split into those naming a verb and those naming a prefix.
    def method_level_names : Array(String)
      @decls.keys.select { |name| resolve(name, [] of String).try { |found| !found.verb.nil? } }
    end

    def class_level_names : Array(String)
      @decls.keys.select { |name| resolve(name, [] of String).try { |found| found.verb.nil? && !found.template.nil? } }
    end

    # What the usage `[name(args)]` means. `args` is the raw argument text.
    def resolve(name : String, args : Array(String)) : Result?
      positional = [] of String?
      named = Hash(String, String?).new
      args.each do |arg|
        if pair = arg.match(NAMED_ARG_RE)
          named[pair[1]] = string_value(pair[2], {} of String => String?, nil)
        else
          positional << string_value(arg, {} of String => String?, nil)
        end
      end
      resolve_values(name, positional, named, 0)
    end

    # Splits the argument list text of a usage (`"a", b: "c"`).
    def self.split_args(text : String) : Array(String)
      args = [] of String
      depth = 0
      quoted = false
      current = String::Builder.new
      chars = text.chars
      i = 0
      while i < chars.size
        char = chars[i]
        if quoted
          current << char
          if char == '\\' && i + 1 < chars.size
            i += 1
            current << chars[i]
          elsif char == '"'
            quoted = false
          end
        elsif char == '"'
          quoted = true
          current << char
        elsif char == ',' && depth == 0
          args << current.to_s.strip
          current = String::Builder.new
        else
          depth += 1 if "([{".includes?(char)
          depth -= 1 if ")]}".includes?(char)
          current << char
        end
        i += 1
      end
      last = current.to_s.strip
      args << last unless last.empty?
      args
    end

    private def resolve_values(name : String, args : Array(String?), named : Hash(String, String?), depth : Int32) : Result?
      key = name.rchop("Attribute")
      if verb = BUILTIN_VERBS[key]?
        return Result.new(verb, args.first?)
      end
      return Result.new(nil, args.first?) if key == "Route"
      return if depth > MAX_DEPTH
      decl = @decls[key]? || return

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
        base_args = ctor.try(&.base_args) || [] of String
        positional = [] of String?
        base_named = Hash(String, String?).new
        base_args.each do |arg|
          if pair = arg.match(NAMED_ARG_RE)
            base_named[pair[1]] = string_value(pair[2], env, decl)
          else
            positional << string_value(arg, env, decl)
          end
        end
        inherited = resolve_values(base, positional, base_named, depth + 1)
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
      elsif m = expr.match(/\A@"((?:[^"]|"")*)"\z/)
        m[1].gsub("\"\"", "\"")
      elsif m = expr.match(/\A"((?:[^"\\]|\\.)*)"\z/)
        m[1].gsub(/\\(.)/) { |_, esc| esc[1] }
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

    private def constructors(body : String, class_name : String) : Array(Ctor)
      ctors = [] of Ctor
      body.scan(/\b(?:public|protected|internal)\s+#{Regex.escape(class_name)}\s*\(/) do |match|
        open = match.end(0) - 1
        close = matching_paren(body, open) || next
        params = CSharpAttributeRoutes.split_args(body[(open + 1)...close]).compact_map do |param|
          pair = param.match(/(\w+)\s*(?:=\s*(.+))?\z/m) || next
          {pair[1], pair[2]?.try(&.strip)}
        end
        base_args = nil
        if tail = body[(close + 1)..].match(/\A\s*:\s*base\s*\(/)
          base_open = close + tail[0].size
          if base_close = matching_paren(body, base_open)
            base_args = CSharpAttributeRoutes.split_args(body[(base_open + 1)...base_close])
          end
        end
        ctors << Ctor.new(params, base_args)
      end
      ctors
    end

    private def constants(body : String) : Hash(String, String)
      found = Hash(String, String).new
      body.scan(CONST_RE) { |match| found[match[1]] = match[2].strip }
      found
    end

    # Index of the `)` closing the `(` at `open`, string literals skipped.
    private def matching_paren(text : String, open : Int32) : Int32?
      depth = 0
      quoted = false
      chars = text.chars
      i = open
      while i < chars.size
        char = chars[i]
        if quoted
          if char == '\\'
            i += 1
          elsif char == '"'
            quoted = false
          end
        elsif char == '"'
          quoted = true
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
    end
  end
end
