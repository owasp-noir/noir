require "../../engines/php_engine"
require "../../../utils/spec_line_index"
require "./symfony_security"

module Analyzer::Php
  class Symfony < PhpEngine
    analyzer_for "php_symfony"

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

    # `$form = $this->createForm(XType::class` or a form factory's
    # `->create(XType::class` / `->createNamed('name', XType::class`.
    FORM_CREATE_RE = /\$(\w+)\s*=\s*\$(?:this->createForm|(?:this->)?\w+->create(?:Named)?)\s*\(\s*(?:['"][^'"]*['"]\s*,\s*)?(\\?[\w\\]+)::class/

    # `$this->forward('Fqcn::method', ...)`: a sub-request on the same input.
    FORWARD_RE  = /\$this->forward\s*\(\s*['"]\\?([\w\\]+)::(\w+)['"]/
    FORM_ADD_RE = /->add\s*\(\s*['"]([^'"]+)['"](#{CALL_ARGS_TAIL})\)/

    # Symfony route configs also live in YAML under config/routes*.
    # Extend the engine's default `.php`-only source set.
    protected def php_source_files : Array(String)
      get_files_by_extension(".php") +
        get_files_by_extension(".yaml") +
        get_files_by_extension(".yml")
    end

    # A YAML route import (`resource: ../src/Controller/Api/`, `type:
    # attribute`, `prefix: /api/v1`): attribute routes in files under `path`
    # are mounted under each of `prefixes`.
    private record RouteImport, path : String, prefixes : Array(String)

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
          imports << RouteImport.new(File.expand_path(resource, File.dirname(path)).rstrip('/'), prefixes)
        end
      end
      imports
    end

    # URL prefixes for a controller file: those of every import covering it,
    # or just "" when no import does.
    private def import_prefixes_for(path : String) : Array(String)
      file = File.expand_path(path)
      prefixes = @route_imports.select { |import| file == import.path || file.starts_with?("#{import.path}/") }
        .flat_map(&.prefixes).uniq!
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
      lexer = Noir::PhpLexer.new(content)
      content = lexer.without_comments

      classes = extract_classes(content, lexer)
      import_prefixes = import_prefixes_for(path)

      # Route annotations (@Route) first, then PHP 8 attributes (#[Route]).
      # Track offset to find each match correctly.
      {/@Route\s*\((.*?)\)/m, /#\[Route\s*\((.*?)\)\]/m}.each do |route_regex|
        offset = 0
        content.scan(route_regex) do |match|
          route_path = extract_symfony_route_path(match[1])
          next unless route_path

          full_match = match[0]

          # Find this specific match starting from current offset
          route_start = content.index(full_match, offset)
          next unless route_start
          offset = route_start + full_match.size
          next if route_applies_to_class?(content, offset)
          # An attribute is code; `#[Route(...)]` written inside a string
          # literal is text. (`@Route` lives in a docblock, so it can't be
          # checked this way.)
          next if full_match.starts_with?('#') && !lexer.in_code?(route_start)

          # Extract methods from the annotation/attribute itself
          methods = extract_methods_from_symfony_context(full_match)
          methods = ["GET"] if methods.empty?

          klass = classes.find { |c| route_start >= c.body_start && route_start < c.body_end }
          action = (sig = content.match(SIGNATURE_RE, offset)) ? action_at(path, content, lexer, sig, klass) : nil
          method_body = action.try(&.body)
          body_params = action.try(&.params) || [] of Param
          route_line = line_number_for_index(content, route_start)
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
      end

      endpoints
    end

    # Every class in the file, with its route prefix and class-level guard.
    private def extract_classes(content : String, lexer : Noir::PhpLexer) : Array(ClassInfo)
      classes = [] of ClassInfo
      # `(?<!::)`: `User::class` in an attribute argument is not a declaration.
      class_regex = /(?<!::)\bclass\s+(\w+)[^{]*\{/m
      offset = 0

      while class_match = content.match(class_regex, offset)
        class_start = class_match.begin(0)
        brace_pos = class_match.end(0) - 1
        class_end = find_matching_php_close_brace(content, brace_pos)
        if class_end
          prefix = route_prefix_before_class(content, class_start) || ""
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
      guard = security_attribute_guard(content[member_prelude_start(content, lexer, sig.begin(0))...sig.begin(0)]) || klass.try(&.guard)
      params = [] of Param
      if body
        sources = [{content, body[0]}] + callee_bodies(content, body[0])
        sources.each { |source, code| params.concat(extract_method_params(code) + form_params(source, code)) }
        guard ||= sources.compact_map { |_, code| refusal_in(code) }.first?
      end
      Action.new(handler, dedup_params(params), guard, body)
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
    private def form_params(content : String, body : String) : Array(Param)
      params = [] of Param
      return params unless body.includes?("::class")
      body.scan(FORM_CREATE_RE) do |m|
        var = Regex.escape(m[1])
        location = if body.matches?(/\$#{var}->handleRequest\s*\(/)
                     "form"
                   elsif submit = body.match(/\$#{var}->submit\s*\(([^;]*)/)
                     submitted_input(submit[1], body)
                   end
        next unless location
        next unless type_file = class_file(qualify_class(m[2], parse_use_imports(content), php_namespace(content)))
        type = php_code(read_file_content(type_file))
        location = "query" if location == "form" && type.matches?(/['"]method['"]\s*=>\s*['"]GET['"]/i)
        params.concat(form_type_fields(type, location))
      end
      params
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

    # Submittable fields a form type's `buildForm` adds. Buttons carry no data
    # and Symfony discards what is submitted for a disabled field.
    private def form_type_fields(type : String, location : String) : Array(Param)
      params = [] of Param
      return params unless build = method_body(type, "buildForm")
      build.scan(FORM_ADD_RE) do |m|
        args = m[2]
        next if args.matches?(/\b(?:Submit|Button|Reset)Type::class/)
        next if args.matches?(/['"]disabled['"]\s*=>\s*true/)
        params << Param.new(m[1], "", args.matches?(/\bFileType::class/) ? "file" : location)
      end
      params
    end

    private def route_prefix_before_class(content : String, class_start : Int32) : String?
      lookbehind_start = Math.max(0, class_start - 600)
      prelude = content[lookbehind_start...class_start]

      if attribute_match = prelude.match(/#\[Route\s*\((.*?)\)\]\s*$/m)
        return extract_symfony_route_path(attribute_match[1])
      end

      if annotation_match = prelude.match(/@Route\s*\((.*?)\).*?\*\/\s*$/m)
        return extract_symfony_route_path(annotation_match[1])
      end

      nil
    end

    # Whether the attribute ending at `route_end` sits on a class: the next
    # declaration after it is `class Name`, not a method. `class:` named
    # arguments and `Foo::class` in the attributes between are neither.
    private def route_applies_to_class?(content : String, route_end : Int32) : Bool
      next_target = content.match(/(?<!::)\b(class\s+\w|function\b)/m, route_end)
      return false unless next_target

      next_target[1].starts_with?("class")
    end

    private def extract_symfony_route_path(context : String) : String?
      # `path:` / `path =` as a standalone key. A multi-line `#[Route(\n  path:
      # '/x',\n  …)]` puts `path` after a newline+indent, which the old
      # `(?:^|[,(]\s*)` anchor missed — so every multi-line route attribute
      # (Shopware's whole storefront) was dropped. A negative-lookbehind on a
      # word char accepts any non-word boundary (start, comma, paren, newline,
      # space) while still rejecting `subpath:` / `routePath:`.
      if path_match = context.match(/(?<!\w)path\s*[:=]\s*['"]([^'"]*)['"]/i)
        return path_match[1]
      end

      if path_match = context.match(/^\s*['"]([^'"]*)['"]/)
        return path_match[1]
      end

      nil
    end

    private def extract_methods_from_symfony_context(context : String) : Array(String)
      methods = [] of String

      if match = context.match(/methods\s*[:=]\s*\[([^\]]+)\]/m)
        methods.concat(extract_method_tokens(match[1]))
      elsif match = context.match(/methods\s*=\s*\{([^}]+)\}/m)
        methods.concat(extract_method_tokens(match[1]))
      elsif match = context.match(/methods\s*[:=]\s*['"]([^'"]+)['"]/)
        methods << match[1].upcase
      elsif match = context.match(/methods\s*[:=]\s*(?:[\w\\]+::)?METHOD_(\w+)/i)
        methods << match[1].upcase
      end

      methods.uniq
    end

    # Methods inside a `methods: [...]` / `={...}` list — either string
    # literals (`'POST'`) or Symfony's `Request::METHOD_POST` constants (used
    # heavily by Shopware), which the string scan alone would have missed and
    # silently defaulted to GET.
    private def extract_method_tokens(list : String) : Array(String)
      tokens = [] of String
      list.scan(/['"]([^'"]+)['"]/) { |m| tokens << m[1].upcase }
      list.scan(/METHOD_(\w+)/i) { |m| tokens << m[1].upcase }
      tokens
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
      klass = extract_classes(content, lexer).find { |c| sig.begin(0) >= c.body_start && sig.begin(0) < c.body_end }
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
