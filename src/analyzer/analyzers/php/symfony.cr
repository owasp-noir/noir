require "../../engines/php_engine"
require "../../../utils/spec_line_index"
require "./symfony_security"
require "./symfony_route_attributes"

module Analyzer::Php
  class Symfony < PhpEngine
    analyzer_for "php_symfony"

    include SymfonyRouteAttributes

    # A class declared in a controller file: its name, its `#[Route]` prefix,
    # the guard its class-level security attributes impose, and its body.
    private record ClassInfo, name : String, prefix : String, guard : String?, body_start : Int32, body_end : Int32

    # What a controller method contributes to the routes it serves.
    private record Action, handler : Handler, params : Array(Param), guard : String?, body : Tuple(String, Int32)?

    SIGNATURE_RE = /(?:public|protected|private)\s+(?:static\s+)?function\s+(\w+)\s*\(/

    # `#[IsGranted('X')]` / `@IsGranted("X")`, with the voted attribute (a
    # literal or a `Class::CONST`) when there is one, or `#[Security("expr")]`.
    # Security must open with its expression string: NelmioApiDoc's
    # `@Security(name="Bearer")` documents a scheme and checks nothing.
    SECURITY_ATTR_RE = /(?:#\[|@)(?:(IsGranted)\s*\(\s*(?:attribute\s*:\s*)?(?:(['"])(.*?)\2|\\?[\w\\]+::(\w+))?|(Security)\s*\(\s*(?:expression\s*:\s*)?['"])/

    # Attributes every caller, anonymous included, is granted.
    PUBLIC_ATTRIBUTES = %w[PUBLIC_ACCESS IS_AUTHENTICATED_ANONYMOUSLY]

    REQUEST_READ_RE = /\$request->(query|request|headers|cookies|files)->(?:get|all|has|getInt|getBoolean|getAlpha|getAlnum|getDigits|getString|getEnum|filter)\s*\(\s*['"]([^'"]+)['"]|\$request->(query|request)->all\(\s*\)\s*\[\s*['"]([^'"]+)['"]|\$request->get\s*\(\s*['"]([^'"]+)['"]/
    REQUEST_BAGS    = {"query" => "query", "request" => "form", "headers" => "header", "cookies" => "cookie", "files" => "file"}

    # `$this->forward('Fqcn::method', ...)`: a sub-request on the same input.
    FORWARD_RE  = /\$this->forward\s*\(\s*['"]\\?([\w\\]+)::(\w+)['"]/
    FORM_ADD_RE = /->add\s*\(\s*['"]([^'"]+)['"](#{CALL_ARGS_TAIL})\)/

    # A form being made: `$this->createForm(X::class` / a factory's
    # `->create(X::class`, or `->createNamed('name', X::class`. The type may
    # be a variable (inside a helper that takes it as an argument).
    FORM_CALL_RE  = /(?:\$this->createForm|->create)\s*\(\s*(?:(\\?[\w\\]+)::class|\$(\w+))/
    FORM_NAMED_RE = /->createNamed\s*\(\s*(?:['"]([^'"]*)['"]|\$\w+)\s*,\s*(?:(\\?[\w\\]+)::class|\$(\w+))/

    # FOSRestBundle's `#[Rest\QueryParam(name: 'page')]` /
    # `@Rest\RequestParam(name="title")` / `FileParam`, which its
    # ParamFetcher reads from the query, the decoded body or the files.
    FOS_PARAM_RE   = /(?:#\[|@)(?:[\w\\]*\\)?(QueryParam|RequestParam|FileParam)\s*\(/
    FOS_PARAM_BAGS = {"QueryParam" => "query", "RequestParam" => "form", "FileParam" => "file"}

    # Packages whose `Route` is Symfony's (or extends it).
    SYMFONY_ROUTE_NAMESPACES = {"Symfony\\", "FOS\\RestBundle\\", "Sensio\\Bundle\\FrameworkExtraBundle\\"}

    # Stands for a form name that cannot be read statically (`createNamed($n,
    # …)`, a computed `getBlockPrefix`); `?` is not valid in a form name.
    UNKNOWN_FORM_NAME = "?"

    # Symfony route configs also live in YAML under config/routes*.
    # Extend the engine's default `.php`-only source set.
    protected def php_source_files : Array(String)
      get_files_by_extension(".php") +
        get_files_by_extension(".yaml") +
        get_files_by_extension(".yml")
    end

    # A YAML route import (`resource: ../src/Controller/Api/`, `type:
    # attribute`, `prefix: /api/v1`): attribute routes in files under `path`
    # are mounted under each of `prefixes`, unless an `excludes` glob matches
    # them. `source` is the routing file that declares it; `name_prefix` and
    # `locales` (the keys of a localized prefix, which renames each route
    # `name.<locale>`) decide the names its routes get.
    private record RouteImport, path : String, prefixes : Array(String), source : String,
      name_prefix : String, locales : Array(String), excludes : Array(String) do
      def covers?(file : String) : Bool
        return false unless file == path || file.starts_with?("#{path}/")
        # Symfony's glob loader skips an excluded file, or a file under an
        # excluded directory.
        candidate = file
        while candidate.size >= path.size
          return false if excludes.any? { |glob| File.match?(glob, candidate) rescue false }
          parent = File.dirname(candidate)
          break if parent == candidate
          candidate = parent
        end
        true
      end
    end

    @route_imports = [] of RouteImport
    @security_configs = [] of SymfonySecurity::Config

    def analyze
      @route_imports = collect_route_imports
      @security_configs = php_source_files.compact_map do |path|
        SymfonySecurity.config?(path) { read_file_content(path) }
      end
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      include_callee = callees_needed?

      # Analyze PHP controller files
      if path.ends_with?(".php")
        endpoints.concat(analyze_php_routes(path, include_callee))
      end

      # Analyze YAML route files
      endpoints.concat(analyze_yaml_routes(path)) if yaml_route_file?(path)

      endpoints.each { |endpoint| tag_access_control(endpoint, path) }
      endpoints
    end

    # A route the firewall's access_control refuses to an anonymous caller.
    # Tagged after any attribute guard, which `add_tag` then keeps.
    private def tag_access_control(endpoint : Endpoint, path : String)
      file = File.expand_path(path)
      config = @security_configs.select { |c| file.starts_with?("#{c.root}/") }.max_by?(&.root.size)
      return unless config && (roles = config.required_roles(endpoint.method, endpoint.url))
      endpoint.add_tag(Tag.new("auth", "Protected by Symfony access_control (#{roles.join(", ")})", "php_auth"))
    end

    private def yaml_route_file?(path : String) : Bool
      (path.ends_with?(".yaml") || path.ends_with?(".yml")) &&
        path.includes?("config") && (path.includes?("routes") || path.includes?("routing"))
    end

    # Every directory/file import declared in the YAML route configs.
    # Imports of other route files (`.yaml`/`.xml`) and bundle paths
    # (`@AcmeBundle/...`) are not followed.
    private def collect_route_imports : Array(RouteImport)
      imports = [] of RouteImport
      php_source_files.each do |path|
        next unless yaml_route_file?(path)
        # A file that fails to parse is reported by `analyze_yaml_routes`.
        routes = begin
          YAML.parse(read_file_content(path)).as_h?
        rescue
          nil
        end
        next unless routes

        routes.each_value do |route|
          route_h = route.as_h?
          next unless route_h
          resource_node = route_h[YAML::Any.new("resource")]?
          resource = resource_node.try { |node| node.as_s? || node.as_h?.try(&.[YAML::Any.new("path")]?.try(&.as_s?)) }
          next if resource.nil? || resource.starts_with?('@') || resource.matches?(/\.(?:ya?ml|xml)\z/i)

          # `prefix` is one path, or a locale => path map.
          prefix_node = route_h[YAML::Any.new("prefix")]?
          prefixes = prefix_node.try { |node| node.as_s?.try { |prefix| [prefix] } || node.as_h?.try(&.values.compact_map(&.as_s?)) }
          prefixes = [""] if prefixes.nil? || prefixes.empty?
          locales = prefix_node.try(&.as_h?).try(&.keys.compact_map(&.as_s?).sort!) || [] of String
          name_prefix = route_h[YAML::Any.new("name_prefix")]?.try(&.as_s?) || ""
          dir = File.dirname(path)
          exclude_node = route_h[YAML::Any.new("exclude")]?
          excludes = (exclude_node.try(&.as_a?).try(&.compact_map(&.as_s?)) || [exclude_node.try(&.as_s?)].compact)
            .map { |glob| File.expand_path(glob, dir).rstrip('/') }
          imports << RouteImport.new(File.expand_path(resource, dir).rstrip('/'), prefixes, path, name_prefix, locales, excludes)
        end
      end
      imports
    end

    # URL prefixes for a controller file: those of the imports covering it,
    # or just "" when no import does. Symfony keys routes by name, and an
    # attribute route keeps its name (one derived from class and method when
    # it declares none) whichever import loads it, so a later import of the
    # same file in the same routing file replaces the earlier one's routes,
    # unless a different `name_prefix`, or a localized prefix (whose routes
    # are renamed `name.<locale>`) over other locales, keeps the names apart.
    private def import_prefixes_for(path : String) : Array(String)
      file = File.expand_path(path)
      prefixes = @route_imports.select(&.covers?(file))
        .group_by { |import| {import.source, import.name_prefix, import.locales} }.values
        .flat_map(&.last.prefixes).uniq!
      prefixes.empty? ? [""] : prefixes
    end

    private def analyze_php_routes(path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      content = read_file_content(path)
      # Controllers/services without route attributes dominate a Symfony
      # tree. Skip the annotation/attribute scans when neither form is
      # present (`@Route` or `#[Route`).
      return endpoints unless content.includes?("Route")
      return endpoints unless content.includes?("@Route") || content.includes?("#[Route")
      # `Route` imported from another package (Spiral's `#[Route(route:
      # '/users')]`) is not Symfony's.
      if (imported = parse_use_imports(content)["Route"]?) && SYMFONY_ROUTE_NAMESPACES.none? { |ns| imported.lchop('\\').starts_with?(ns) }
        return endpoints
      end
      lexer = Noir::PhpLexer.new(content)
      content = lexer.without_comments

      attrs = route_attributes(content, lexer)
      classes = extract_classes(content, lexer, attrs)
      import_prefixes = import_prefixes_for(path)

      attrs.each do |attr|
        next if route_applies_to_class?(content, attr.stop)
        next unless route_path = extract_symfony_route_path(attr.args)
        next if docblock_orphaned?(content, attr)

        methods = extract_methods_from_symfony_context(attr.args)
        methods = ["GET"] if methods.empty?

        klass = classes.find { |c| attr.start >= c.body_start && attr.start < c.body_end }
        action = (sig = content.match(SIGNATURE_RE, attr.stop)) ? action_at(path, content, lexer, sig, klass) : nil
        method_body = action.try(&.body)
        body_params = action.try(&.params) || [] of Param
        route_line = line_number_for_index(content, attr.start)
        class_path = build_full_path(klass.try(&.prefix) || "", route_path)

        import_prefixes.each do |import_prefix|
          full_path = build_full_path(import_prefix, class_path).presence || "/"
          params = dedup_params(extract_brace_path_params(full_path) + body_params)

          methods.each do |method|
            details = Details.new(PathInfo.new(path, route_line))
            endpoint = Endpoint.new(full_path, method.upcase, params, details)
            endpoint = apply_action(endpoint, action)
            attach_method_callees(endpoint, method_body, path) if include_callee
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # Every class in the file, with its route prefix and class-level guard.
    private def extract_classes(content : String, lexer : Noir::PhpLexer, attrs : Array(RouteAttr)) : Array(ClassInfo)
      classes = [] of ClassInfo
      # `(?<!::)`: `User::class` in an attribute argument is not a declaration.
      class_regex = /(?<!::)\bclass\s+(\w+)[^{]*\{/m
      offset = 0

      while class_match = content.match(class_regex, offset)
        class_start = class_match.begin(0)
        brace_pos = class_match.end(0) - 1
        class_end = find_matching_php_close_brace(content, brace_pos)
        if class_end
          # The route attribute this class declaration is the next one after.
          attr = attrs.reverse_each.find { |a| a.stop <= class_start }
          on_class = attr && (decl = next_declaration(content, attr.stop)) && decl.begin(0) == class_start
          prefix = (attr && on_class ? extract_symfony_route_path(attr.args) : nil) || ""
          guard = security_attribute_guard(content[member_prelude_start(content, lexer, class_start)...class_start])
          classes << ClassInfo.new(class_match[1], prefix, guard, brace_pos + 1, class_end)
          offset = class_end + 1
        else
          offset = class_match.end(0)
        end
      end

      classes
    end

    # Start of the attributes/docblock in front of the declaration at `pos`:
    # just past the previous `;`, `{` or `}` that is code.
    private def member_prelude_start(content : String, lexer : Noir::PhpLexer, pos : Int32) : Int32
      i = pos
      while i > 0 && (i = content.rindex(/[;{}]/, i - 1))
        return i + 1 if lexer.in_code?(i)
      end
      0
    end

    # The first security attribute in `prelude` that can refuse an anonymous
    # caller. `IsGranted('PUBLIC_ACCESS')` (or the pre-5.1
    # `IS_AUTHENTICATED_ANONYMOUSLY`) grants everyone, so it guards nothing.
    private def security_attribute_guard(prelude : String) : String?
      return unless prelude.includes?("IsGranted") || prelude.includes?("Security")
      prelude.scan(SECURITY_ATTR_RE) do |m|
        return "Symfony #[Security]" if m[5]?
        attribute = m[3]? || m[4]?
        next if attribute && PUBLIC_ATTRIBUTES.includes?(attribute)
        return attribute ? "Symfony #[IsGranted('#{attribute}')]" : "Symfony #[IsGranted]"
      end
      nil
    end

    # Handler, request params and guard of the method whose signature is `sig`.
    private def action_at(path : String, content : String, lexer : Noir::PhpLexer, sig : Regex::MatchData, klass : ClassInfo?) : Action
      body = extract_php_method_body_after(content, sig.begin(0))
      name = klass ? "#{klass.name}::#{sig[1]}" : sig[1]
      handler = Handler.new(name, path, line_number_for_index(content, sig.begin(1)))
      prelude = content[member_prelude_start(content, lexer, sig.begin(0))...sig.begin(0)]
      guard = security_attribute_guard(prelude) || klass.try(&.guard)
      params = fos_rest_params(prelude)
      if body
        sources = [{content, body[0]}] + callee_bodies(content, body[0])
        sources.each { |source, code| params.concat(extract_method_params(code) + form_params(source, code)) }
        guard ||= sources.compact_map { |_, code| refusal_in(code) }.first?
      end
      Action.new(handler, dedup_params(params), guard, body)
    end

    # The request key of each FOSRest param attribute on an action: its `key`
    # alias when it has one, else its `name` (named or first positional).
    private def fos_rest_params(prelude : String) : Array(Param)
      params = [] of Param
      return params unless prelude.includes?("Param")
      prelude.scan(FOS_PARAM_RE) do |m|
        open = m.end(0) - 1
        block = prelude[open..]
        next unless close = Noir::PhpLexer.new(block, php_mode: true).matching_delimiter(0)
        named, positional = attribute_args(block[1...close].gsub(/\n\s*\*/, "\n"))
        key = (named["key"]? || named["name"]? || positional.first?).try { |expr| php_literal(expr) }.presence
        params << Param.new(key, "", FOS_PARAM_BAGS[m[1]]) if key
      end
      params
    end

    # `Endpoint` is a struct: callers keep the returned copy.
    private def apply_action(endpoint : Endpoint, action : Action?) : Endpoint
      return endpoint unless action
      endpoint.handler = action.handler
      action.guard.try { |guard| endpoint.add_tag(Tag.new("auth", "Protected by #{guard}", "php_auth")) }
      endpoint
    end

    # {source, body} of what an action calls, one level deep: its own class's
    # (or the parent's) `$this->foo(` helpers, `parent::foo(`, and the
    # controller a `$this->forward('Fqcn::foo')` sub-request runs on the same
    # input.
    private def callee_bodies(content : String, body : String) : Array(Tuple(String, String))
      bodies = [] of Tuple(String, String)
      parent = nil
      body.scan(/\$this->(\w+)\s*\(/).map(&.[1]).uniq!.each do |name|
        if helper = method_body(content, name)
          bodies << {content, helper}
        elsif (parent ||= parent_source(content)) && (inherited = method_body(parent, name))
          bodies << {parent, inherited}
        end
      end
      body.scan(/\bparent::(\w+)\s*\(/).map(&.[1]).uniq!.each do |name|
        parent ||= parent_source(content)
        method_body(parent, name).try { |inherited| bodies << {parent, inherited} }
      end
      body.scan(FORWARD_RE) do |m|
        next unless file = class_file(m[1])
        target = php_code(read_file_content(file))
        method_body(target, m[2]).try { |forwarded| bodies << {target, forwarded} }
      end
      bodies
    end

    # A check in `body` that refuses a caller lacking a (non-public)
    # attribute: `denyAccessUnlessGranted('X')`, or `isGranted('X')` next to
    # an `AccessDenied` throw.
    private def refusal_in(body : String) : String?
      return unless body.includes?("Granted")
      if (m = body.match(/denyAccessUnlessGranted\s*\(\s*['"](\w+)['"]/)) && !PUBLIC_ATTRIBUTES.includes?(m[1])
        return "Symfony denyAccessUnlessGranted('#{m[1]}')"
      end
      if body.includes?("AccessDenied") && (m = body.match(/isGranted\s*\(\s*['"](\w+)['"]/)) && !PUBLIC_ATTRIBUTES.includes?(m[1])
        "Symfony isGranted('#{m[1]}') check"
      end
    end

    private def method_body(content : String, name : String) : String?
      sig = content.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+#{Regex.escape(name)}\s*\(/)
      sig.try { |m| extract_php_method_body_after(content, m.begin(0)).try(&.[0]) }
    end

    private def php_namespace(content : String) : String?
      content.match(/\bnamespace\s+([\w\\]+)\s*[;{]/).try(&.[1])
    end

    # The file declaring `fqcn`: a `<Short>.php` whose namespace matches.
    private def class_file(fqcn : String) : String?
      namespace, _, short = fqcn.lchop('\\').rpartition('\\')
      get_files_by_basename("#{short}.php").find do |file|
        (php_namespace(read_file_content(file)) || "") == namespace
      end
    end

    # The parent class's comment-stripped source, or "" when it is not in the tree.
    private def parent_source(content : String) : String
      parent = content.match(/(?<!::)\bclass\s+\w+\s+extends\s+(\\?[\w\\]+)/).try(&.[1])
      file = parent.try { |ref| class_file(qualify_class(ref, parse_use_imports(content), php_namespace(content))) }
      file ? php_code(read_file_content(file)) : ""
    end

    # Fields of each form `body` creates and binds to the request. Only a
    # bound form reads input: `handleRequest($request)` reads the body (the
    # query for a `'method' => 'GET'` form); `submit($x)` reads whatever `$x`
    # was taken from. A form submitted from a literal array reads nothing.
    #
    # `handleRequest` reads the fields under the form's name (`edit[title]`),
    # plus its CSRF token when the type turns CSRF protection on; `submit`
    # is handed the field data itself, so its fields are bare.
    private def form_params(content : String, body : String) : Array(Param)
      params = [] of Param
      return params unless body.includes?("::class") || body.includes?("$this->")
      body.scan(/\$(\w+)\s*=\s*([^;]+);/) do |m|
        var = "$#{m[1]}->"
        handled = body.includes?("#{var}handleRequest(")
        location = if handled
                     "form"
                   elsif submit = body.index("#{var}submit(")
                     arg_start = submit + var.size + "submit(".size
                     submitted_input(body[arg_start...(body.index(';', arg_start) || body.size)], body)
                   end
        next unless location
        next unless form = created_form(m[2], content)
        type_file, name, call = form
        type = php_code(read_file_content(type_file))
        get_method = /['"]method['"]\s*=>\s*['"]GET['"]/i
        location = "query" if location == "form" && (call.matches?(get_method) || type.matches?(get_method))
        fields = form_type_fields(type, location)
        if handled
          name ||= form_name(type, type_file)
          # The fields sit under a name we cannot read: listing them bare
          # would name inputs the form does not read.
          next if name == UNKNOWN_FORM_NAME
          csrf_field(type).try { |field| fields << Param.new(field, "", location) }
          fields.map! { |field| Param.new("#{name}[#{field.name}]", "", field.param_type) } unless name.empty?
        end
        params.concat(fields)
      end
      params
    end

    # {type file, form name (nil: the type's own), creating call} of the form
    # `expr` makes: a direct create call with a literal type, or a call to a
    # helper of the class (or a parent or trait) that makes one, from a
    # literal type of its own or from the `X::class` it is handed in the
    # parameter the helper creates the form from.
    private def created_form(expr : String, content : String) : Tuple(String, String?, String)?
      if (call = form_call(expr)) && (type = call[1])
        file = class_file(qualify_class(type, parse_use_imports(content), php_namespace(content)))
        return file ? {file, call[0], expr} : nil
      end
      return unless (helper = expr.match(/\A\s*\$this->(\w+)\s*\(/)) && helper[1] != "createForm"
      return unless (resolved = resolve_method(content, helper[1])) && (call = form_call(resolved[1]))
      source, code = resolved
      type, scope = if literal = call[1]
                      {literal, source}
                    elsif (var = call[2]) && (index = helper_param_index(source, helper[1], var))
                      open = helper.end(0) - 1
                      close = Noir::PhpLexer.new(expr, php_mode: true).matching_delimiter(open)
                      arg = close ? split_php_args(expr[open + 1...close])[index]? : nil
                      {arg.try(&.match(/\A(\\?[\w\\]+)::class\z/)).try(&.[1]), content}
                    else
                      {nil, content}
                    end
      return unless type && (file = class_file(qualify_class(type, parse_use_imports(scope), php_namespace(scope))))
      {file, call[0], code}
    end

    # Position of parameter `$var` in method `name`'s signature in `source`.
    private def helper_param_index(source : String, name : String, var : String) : Int32?
      sig = source.match(/function\s+#{Regex.escape(name)}\s*\(([^)]*)\)/)
      sig.try(&.[1].split(',').index { |param| param.match(/\$(\w+)/).try(&.[1]) == var })
    end

    # {form name (nil: the type's own; UNKNOWN_FORM_NAME when not a
    # literal), literal type, type variable} of the first form-creating call
    # in `code`.
    private def form_call(code : String) : Tuple(String?, String?, String?)?
      named = code.match(FORM_NAMED_RE)
      plain = code.match(FORM_CALL_RE)
      if named && (plain.nil? || named.begin(0) < plain.begin(0))
        {named[1]? || UNKNOWN_FORM_NAME, named[2]?, named[3]?}
      elsif plain
        {nil, plain[1]?, plain[2]?}
      end
    end

    # A form type's name: what its `getBlockPrefix` returns (a literal, or a
    # string constant of the class), or Symfony's default, the class's short
    # name without a `Type` suffix in snake case (`fqcnToBlockPrefix`).
    # UNKNOWN_FORM_NAME when the override computes it.
    private def form_name(type : String, type_file : String) : String
      if prefix = resolve_method(type, "getBlockPrefix")
        source, code = prefix
        returned = code.match(/\breturn\s+([^;]+);\s*\z/).try(&.[1].strip)
        if constant = returned.try(&.match(/\A(?:self|static)::(\w+)\z/))
          returned = source.match(/\bconst\s+(?:string\s+)?#{Regex.escape(constant[1])}\s*=\s*([^;]+);/).try(&.[1].strip)
        end
        return returned.try { |expr| php_literal(expr) } || UNKNOWN_FORM_NAME
      end
      short = type.match(/(?<!::)\bclass\s+(\w+)/).try(&.[1]) || File.basename(type_file, ".php")
      short = short.sub(/type\z/i, "") unless short.size <= 4
      short.gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2").gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase
    end

    # The CSRF token field a type's options turn on (`'csrf_protection' =>
    # true`, named by `csrf_field_name`, `_token` by default).
    # ponytail: only an explicit `true` counts; the app-wide default and form
    # type extensions that switch it off are not read.
    private def csrf_field(type : String) : String?
      return unless (options = resolve_method(type, "configureOptions")) &&
                    options[1].matches?(/['"]csrf_protection['"]\s*=>\s*true\b/)
      options[1].match(/['"]csrf_field_name['"]\s*=>\s*['"]([^'"]+)['"]/).try(&.[1]) || "_token"
    end

    # {source, body} of method `name` as the class in `content` resolves it:
    # its own, a trait's it uses, else its parent's (recursively).
    private def resolve_method(content : String, name : String, depth : Int32 = 0) : Tuple(String, String)?
      if body = method_body(content, name)
        return {content, body}
      end
      return if depth > 4 || content.empty?
      trait_sources(content).each do |trait|
        resolve_method(trait, name, depth + 1).try { |found| return found }
      end
      resolve_method(parent_source(content), name, depth + 1)
    end

    # Comment-stripped sources of the traits the class in `content` uses.
    private def trait_sources(content : String) : Array(String)
      return [] of String unless klass = content.match(/(?<!::)\b(?:class|trait)\s+\w+[^{]*\{/)
      header = content[0...klass.begin(0)]
      imports = parse_use_imports(header)
      namespace = php_namespace(header)
      content[klass.end(0)..].scan(/(?:\A|[;{}])\s*use\s+(\\?[\w\\]+(?:\s*,\s*\\?[\w\\]+)*)\s*[;{]/).flat_map do |m|
        m[1].split(',').compact_map do |ref|
          class_file(qualify_class(ref.strip, imports, namespace)).try { |file| php_code(read_file_content(file)) }
        end
      end
    end

    # Where the data handed to `$form->submit(...)` came from, or nil.
    private def submitted_input(arg : String, body : String, depth : Int32 = 0) : String?
      # A literal array is built by the action; its request reads are already
      # params of their own, and its keys are not request input.
      return if arg.lstrip.starts_with?('[') || arg.lstrip.starts_with?("array(")
      return "query" if arg.includes?("$request->query")
      return "json" if arg.includes?("json_decode") || arg.includes?("toArray(")
      return "form" if arg.includes?("$request->request")
      return if depth > 0
      var = arg.match(/\A\s*\$(\w+)\s*[,)]/).try(&.[1])
      assigned = var.try { |name| body.match(/\$#{Regex.escape(name)}\s*=\s*([^;]+);/) }
      assigned.try { |a| submitted_input(a[1], body, depth + 1) }
    end

    # Submittable fields a form type's `buildForm` (its own or inherited)
    # adds, including through the `$this->helper(` / `parent::buildForm(`
    # calls it makes. Buttons carry no data and Symfony discards what is
    # submitted for a disabled field.
    private def form_type_fields(type : String, location : String, depth : Int32 = 0) : Array(Param)
      params = [] of Param
      return params unless found = resolve_method(type, "buildForm")
      source, build = found
      codes = [build]
      build.scan(/\$this->(\w+)\s*\(/).map(&.[1]).uniq!.each do |helper|
        resolve_method(source, helper).try { |resolved| codes << resolved[1] }
      end
      if depth < 4 && build.matches?(/\bparent::buildForm\s*\(/)
        params.concat(form_type_fields(parent_source(source), location, depth + 1))
      end
      codes.join('\n').scan(FORM_ADD_RE) do |m|
        args = m[2]
        next if args.matches?(/\b(?:Submit|Button|Reset)Type::class/)
        next if args.matches?(/['"]disabled['"]\s*=>\s*true/)
        params << Param.new(m[1], "", args.matches?(/\bFileType::class/) ? "file" : location)
      end
      params
    end

    # A docblock `@Route` that documents nothing: what follows the docblock
    # is not a declaration (its method was commented out, which
    # `without_comments` blanked) — Symfony registers no route for it.
    DOCBLOCK_FOLLOWER_RE = /\G\s*(?:#\[|(?:(?:public|protected|private|static|final|abstract|readonly)\s+)*(?:function|class)\b)/

    private def docblock_orphaned?(content : String, attr : RouteAttr) : Bool
      return false unless content[attr.start]? == '@'
      close = content.index("*/", attr.stop) || return false
      !content.match(DOCBLOCK_FOLLOWER_RE, close + 2)
    end

    private def analyze_yaml_routes(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      begin
        content = read_file_content(path)

        # Simple YAML route parsing for Symfony
        # Look for patterns like:
        # route_name:
        #   path: /api/users/{id}
        #   methods: [GET, POST]

        yaml = YAML.parse(content)
        # A route in a Symfony YAML routing file is declared by its name key,
        # so that key's line is where a reviewer has to look.
        line_index = Noir::SpecLineIndex.yaml(content, max_depth: 1)
        if routes = yaml.as_h?
          routes.each do |route_name, route|
            route_h = route.as_h?
            next unless route_h

            route_path = route_h[YAML::Any.new("path")]?.try(&.as_s?)
            next unless route_path

            methods = extract_yaml_methods(route_h[YAML::Any.new("methods")]?)
            methods = ["GET"] if methods.empty?

            action = yaml_action(route_h)
            params = dedup_params(extract_brace_path_params(route_path) + (action.try(&.params) || [] of Param))
            route_line = route_name.as_s?.try { |name| line_index.line(name) }

            methods.each do |method|
              details = Details.new(PathInfo.new(path, route_line))
              endpoint = Endpoint.new(route_path, method.upcase, params, details)
              endpoint = apply_action(endpoint, action)
              endpoints << endpoint
            end
          end
        end
      rescue e
        logger.debug "Error parsing YAML routes in #{path}: #{e}"
        Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      end

      endpoints
    end

    # The controller method a YAML route's `controller:` (or
    # `defaults: {_controller: ...}`) names as `Fqcn::method`, or an
    # invocable `Fqcn`. Service ids (`app.foo:bar`) are not resolved.
    private def yaml_action(route_h : Hash(YAML::Any, YAML::Any)) : Action?
      ref = route_h[YAML::Any.new("controller")]?.try(&.as_s?) ||
            route_h[YAML::Any.new("defaults")]?.try(&.as_h?).try(&.[YAML::Any.new("_controller")]?).try(&.as_s?)
      return unless ref && (m = ref.match(/\A\\?([A-Za-z_][\w\\]*)(?:::(\w+))?\z/))
      return unless file = class_file(m[1])
      lexer = Noir::PhpLexer.new(read_file_content(file))
      content = lexer.without_comments
      method = Regex.escape(m[2]? || "__invoke")
      return unless sig = content.match(/(?:public|protected|private)\s+(?:static\s+)?function\s+(#{method})\s*\(/)
      klass = extract_classes(content, lexer, [] of RouteAttr).find { |c| sig.begin(0) >= c.body_start && sig.begin(0) < c.body_end }
      action_at(file, content, lexer, sig, klass)
    end

    private def extract_yaml_methods(node : YAML::Any?) : Array(String)
      return [] of String unless node

      if methods = node.as_a?
        methods.compact_map(&.as_s?).reject(&.empty?)
      elsif method = node.as_s?
        method.empty? ? [] of String : [method]
      else
        [] of String
      end
    end

    # `$request->query->get('x')`, `->all('x')`, `->getInt('x')`, ... per
    # request bag, `$request->request->all()['x']`, and the bag-agnostic
    # `$request->get('x')` (reported as query).
    private def extract_method_params(method_body : String) : Array(Param)
      params = [] of Param
      return params unless method_body.includes?("$request")

      method_body.scan(REQUEST_READ_RE) do |m|
        if bag = m[1]?
          params << Param.new(m[2], "", REQUEST_BAGS[bag])
        elsif bag = m[3]?
          params << Param.new(m[4], "", REQUEST_BAGS[bag])
        else
          params << Param.new(m[5], "", "query")
        end
      end
      dedup_params(params)
    end
  end
end
