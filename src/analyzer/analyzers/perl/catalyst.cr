require "../../engines/perl_engine"

module Analyzer::Perl
  class Catalyst < PerlEngine
    HTTP_VERBS        = %w[get post put delete patch options head]
    BARE_ATTR_VALUE   = "__NOIR_BARE_ATTR__"
    HTTP_METHOD_ATTRS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "option"  => "OPTIONS",
      "options" => "OPTIONS",
      "head"    => "HEAD",
    }

    private struct ControllerConfig
      property namespace_override, path_override, roles, parents, action_pathparts

      def initialize(@namespace_override : String? = nil,
                     @path_override : String? = nil,
                     @roles : Array(String) = [] of String,
                     @parents : Array(String) = [] of String,
                     @action_pathparts : Hash(String, String) = {} of String => String)
      end
    end

    private struct RouteAction
      property base_path, name, package_name, namespace, path_prefix, attrs, body, file_path, line

      def initialize(@base_path : String,
                     @name : String,
                     @package_name : String,
                     @namespace : String,
                     @path_prefix : String,
                     @attrs : Hash(String, Array(String)),
                     @body : String,
                     @file_path : String,
                     @line : Int32)
      end
    end

    def analyze
      actions = [] of RouteAction
      configs = {} of String => ControllerConfig
      actions_mutex = Mutex.new
      parallel_file_scan do |path|
        next unless catalyst_source_file?(path)

        content = read_file_content(path)
        file_actions = collect_actions(content, path)
        file_configs = collect_controller_configs(sanitize_perl_lines(content.lines))
        actions_mutex.synchronize do
          actions.concat(file_actions)
          file_configs.each { |pkg, cfg| configs[pkg] = cfg }
        end
      end

      @result.concat(analyze_actions(compose_actions(actions, configs)))
      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless catalyst_source_file?(path)

      content = read_file_content(path)
      analyze_content(content, path)
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      actions = collect_actions(content, file_path)
      configs = collect_controller_configs(sanitize_perl_lines(content.lines))
      analyze_actions(compose_actions(actions, configs))
    end

    private def analyze_actions(actions : Array(RouteAction)) : Array(Endpoint)
      actions_by_name = actions_by_name(actions)
      actions_by_private = actions_by_private(actions)
      rest_handlers = rest_handlers(actions, actions_by_name)
      endpoints = [] of Endpoint

      actions.each do |action|
        next if rest_handler_action?(action, rest_handlers)
        next if attr_present?(action, "chained") && attr_present?(action, "captureargs")
        next unless dispatch_action?(action)

        path = if attr_present?(action, "chained")
                 chained_path(action, actions_by_name, actions_by_private, [] of String)
               else
                 direct_path(action)
               end
        next if path.nil?
        path = append_args(path, attr_values(action, "args"), "arg")

        method_handlers = rest_handlers[action_key(action)]? || {} of String => RouteAction
        methods = methods_for_action(action, method_handlers)
        methods.each do |method|
          params = [] of Param
          extract_path_params(path).each { |param| push_unique_param(params, param) }
          extract_params_from_body(action.body, method).each { |param| push_unique_param(params, param) }
          if handler = method_handlers[method]?
            extract_params_from_body(handler.body, method).each { |param| push_unique_param(params, param) }
          end

          endpoint = Endpoint.new(path, method, params)
          endpoint.details = Details.new(PathInfo.new(action.file_path, action.line))
          endpoints << endpoint
        end
      end

      endpoints
    end

    # Flatten Moose role / base-class composition into each controller.
    #
    # Catalyst apps build CRUD/URIStructure chains by defining the terminal
    # actions in one role and the `base`/`object`/`setup` chain links in
    # sibling roles, then composing them all into a controller with
    # `with`/`extends`. At runtime the actions live in the controller's
    # namespace, so the chain resolves; statically each piece sits in its own
    # package and the chain dead-ends (handled conservatively by skipping the
    # fragment in `chained_path`).
    #
    # Here we recreate the runtime view: every action reachable through a
    # controller's transitive `with`/`extends` graph is copied into that
    # controller (re-keyed to its package, with any
    # `config(action => { name => { PathPart => ... } })` override applied), so
    # the relative chains now resolve within one package and produce the real
    # paths (`/building/create`, `/<repo>/tree`). The originals stay in their
    # role packages and remain skipped, so this only adds resolved routes.
    private def compose_actions(actions : Array(RouteAction),
                                configs : Hash(String, ControllerConfig)) : Array(RouteAction)
      return actions if configs.empty?

      actions_by_package = Hash(String, Array(RouteAction)).new
      actions.each { |action| (actions_by_package[action.package_name] ||= [] of RouteAction) << action }

      extras = [] of RouteAction
      configs.each do |pkg, config|
        next unless controller_package?(pkg)
        next if config.roles.empty? && config.parents.empty?
        own = actions_by_package[pkg]? || [] of RouteAction

        # Re-keyed actions need the controller's routing context. Take it from
        # one of the controller's own actions when present; otherwise (a pure
        # composition controller with no methods of its own) derive it from
        # the package name and config.
        if first = own.first?
          template_base = first.base_path
          template_namespace = first.namespace
          template_prefix = first.path_prefix
        else
          template_namespace = controller_namespace(pkg, config)
          template_base = ""
          template_prefix = path_prefix(template_namespace, config)
        end

        seen = Set(String).new
        own.each { |action| seen << action.name }

        composition_sources(pkg, configs).each do |source_pkg|
          (actions_by_package[source_pkg]? || [] of RouteAction).each do |action|
            # Only chained actions compose: a relative chain (`Chained('base')`)
            # resolves within the controller once re-keyed. Path/Local/Global
            # actions dispatch off the *defining* namespace, so a subclass that
            # `extends` a concrete controller must not re-home them under its
            # own namespace (that invents `/transactions/stripe/cash/credit`).
            next unless action.attrs.has_key?("chained")
            next unless seen.add?(action.name)
            attrs = action.attrs.dup
            if pathpart = config.action_pathparts[action.name]?
              attrs["pathpart"] = [pathpart]
            end
            extras << RouteAction.new(
              template_base, action.name, pkg, template_namespace,
              template_prefix, attrs, action.body, action.file_path, action.line
            )
          end
        end
      end

      extras.empty? ? actions : actions + extras
    end

    # Packages a chained role action is composed *into* — Catalyst dispatches
    # only `::Controller::` classes; `::ControllerRole::`/`::ControllerBase::`
    # and `::URIStructure::` are role/base sources, never controllers.
    private def controller_package?(package_name : String) : Bool
      package_name.includes?("::Controller::")
    end

    # Transitive `with` roles + `extends` parents of a package (in-repo only;
    # external bases like `Catalyst::Controller` simply have no config entry).
    private def composition_sources(pkg : String, configs : Hash(String, ControllerConfig)) : Array(String)
      sources = [] of String
      visited = Set(String).new
      visited << pkg
      queue = Deque(String).new
      if config = configs[pkg]?
        config.roles.each { |role| queue << role }
        config.parents.each { |parent| queue << parent }
      end

      while node = queue.shift?
        next unless visited.add?(node)
        sources << node
        if config = configs[node]?
          config.roles.each { |role| queue << role }
          config.parents.each { |parent| queue << parent }
        end
      end

      sources
    end

    private def collect_actions(content : String, file_path : String) : Array(RouteAction)
      raw_lines = content.lines
      lines = sanitize_perl_lines(raw_lines)
      # Count braces over a string/comment/regex-stripped (line-aligned) view so
      # an unbalanced brace inside a literal can't truncate/extend a sub body.
      code_lines = code_only_lines(lines)
      package_configs = collect_controller_configs(lines)
      actions = [] of RouteAction
      package_name = ""
      base_path = configured_base_for(file_path)
      index = 0

      while index < lines.size
        line = lines[index]
        if package_match = line.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_:]*)\s*;/)
          package_name = package_match[1]
        end

        sub_match = line.match(/^\s*sub\s+([A-Za-z_][A-Za-z0-9_]*)\b(.*)$/)
        unless sub_match
          index += 1
          next
        end

        start_index = index
        name = sub_match[1]
        declaration = line
        while !declaration.includes?("{") && !declaration.includes?(";") && index + 1 < lines.size
          index += 1
          declaration += " " + lines[index].strip
        end

        body_lines = [] of String
        if declaration.includes?("{")
          brace_depth = 0
          opened = false
          body_index = start_index
          while body_index < lines.size
            body_line = lines[body_index]
            body_lines << body_line
            code_line = code_lines[body_index]? || ""
            brace_depth += brace_delta(code_line)
            opened = true if code_line.includes?("{")
            break if opened && brace_depth <= 0
            body_index += 1
          end
          index = body_index
        end

        attrs = parse_attrs(declaration)
        config = package_configs[package_name]? || ControllerConfig.new
        namespace = controller_namespace(package_name, config)
        actions << RouteAction.new(
          base_path,
          name,
          package_name,
          namespace,
          path_prefix(namespace, config),
          attrs,
          body_lines.join("\n"),
          file_path,
          start_index + 1
        )
        index += 1
      end

      actions
    end

    private def collect_controller_configs(lines : Array(String)) : Hash(String, ControllerConfig)
      namespaces = {} of String => String
      paths = {} of String => String
      roles = Hash(String, Array(String)).new
      parents = Hash(String, Array(String)).new
      pathparts = Hash(String, Hash(String, String)).new
      package_name = ""
      index = 0

      while index < lines.size
        line = lines[index]
        if package_match = line.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_:]*)\s*;/)
          package_name = package_match[1]
        end

        stripped = line.lstrip
        # `with 'Role'` / `with ('A', 'B')` / multi-line `with\n  'A',\n  'B';`
        # — Moose role application. Roles are composition sources whose
        # chained actions belong to the consuming controller.
        if stripped.matches?(/^with\b/)
          statement, index = accumulate_statement(lines, index)
          (roles[package_name] ||= [] of String).concat(extract_quoted_packages(statement))
          next
        end

        # `extends 'Base'` / `BEGIN { extends 'Base' }` — base-class
        # inheritance, another composition source.
        if stripped.includes?("extends")
          (parents[package_name] ||= [] of String).concat(extract_extends_packages(line))
        end

        unless line.includes?("__PACKAGE__->config")
          index += 1
          next
        end

        statement, index = accumulate_statement(lines, index)
        if namespace_override = config_value(statement, "namespace")
          namespaces[package_name] ||= namespace_override
        end
        if path_override = config_value(statement, "path")
          paths[package_name] ||= path_override
        end
        extract_action_pathparts(statement).each do |action, pathpart|
          (pathparts[package_name] ||= {} of String => String)[action] ||= pathpart
        end
        next
      end

      configs = {} of String => ControllerConfig
      keys = (namespaces.keys + paths.keys + roles.keys + parents.keys + pathparts.keys).uniq
      keys.each do |pkg|
        next if pkg.empty?
        configs[pkg] = ControllerConfig.new(
          namespaces[pkg]?,
          paths[pkg]?,
          roles[pkg]? || [] of String,
          parents[pkg]? || [] of String,
          pathparts[pkg]? || {} of String => String,
        )
      end
      configs
    end

    # Join a statement that may wrap across lines into one string, returning
    # it together with the index of its final physical line.
    private def accumulate_statement(lines : Array(String), start : Int32) : Tuple(String, Int32)
      statement = lines[start]
      index = start
      while !statement.includes?(";") && index + 1 < lines.size && (index - start) < 64
        index += 1
        statement += " " + lines[index].strip
      end
      {statement, index + 1}
    end

    private def extract_quoted_packages(statement : String) : Array(String)
      packages = [] of String
      statement.scan(/['"]([A-Za-z_][A-Za-z0-9_:]+)['"]/) { |m| packages << m[1] }
      packages
    end

    private def extract_extends_packages(line : String) : Array(String)
      tail = line.sub(/^.*?extends/, "")
      extract_quoted_packages(tail)
    end

    # Per-action `PathPart` overrides from `config(action => { name => {
    # PathPart => 'x' } })`. `PathPart` only ever appears inside an action
    # block, so matching `name => { PathPart => '...' }` directly is precise.
    private def extract_action_pathparts(statement : String) : Hash(String, String)
      overrides = {} of String => String
      statement.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=>\s*\{\s*PathPart\s*=>\s*(['"])([^'"]*)\2/) do |m|
        overrides[m[1]] = m[3]
      end
      overrides
    end

    private def config_value(statement : String, key : String) : String?
      patterns = [
        /#{key}\s*=>\s*q\{([^}]*)\}/,
        /#{key}\s*=>\s*q\(([^)]*)\)/,
        /#{key}\s*=>\s*q\/([^\/]*)\//,
        /#{key}\s*=>\s*'([^']*)'/,
        /#{key}\s*=>\s*"([^"]*)"/,
      ]

      patterns.each do |pattern|
        if m = statement.match(pattern)
          return clean_path_prefix(m[1])
        end
      end
    end

    private def parse_attrs(declaration : String) : Hash(String, Array(String))
      attrs = {} of String => Array(String)
      attr_text = declaration.sub(/^\s*sub\s+[A-Za-z_][A-Za-z0-9_]*\b/, "")
      attr_text = attr_text.split("{", 2)[0].split(";", 2)[0]
      attr_text.scan(/:?\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\s*([^)]+?)\s*\))?/) do |match|
        name = match[1].downcase
        attrs[name] ||= [] of String
        if value = match[2]?
          attrs[name] << clean_attr_value(value)
        else
          attrs[name] << BARE_ATTR_VALUE
        end
      end
      attrs
    end

    private def direct_path(action : RouteAction) : String?
      prefix = namespace_path(action.path_prefix)

      if attr_present?(action, "path")
        value = first_attr(action, "path")
        value = "" if bare_attr_value?(value)
        return normalize_path(value) if value.starts_with?("/")
        return join_url(prefix, value)
      end

      return prefix.empty? ? "/" : normalize_path(prefix) if attr_present?(action, "index")
      return join_url(prefix, action.name) if attr_present?(action, "local")
      return normalize_path(action.name) if attr_present?(action, "global")

      nil
    end

    private def chained_path(action : RouteAction,
                             actions_by_name : Hash(String, RouteAction),
                             actions_by_private : Hash(String, RouteAction),
                             seen : Array(String)) : String?
      key = action_key(action)
      return if seen.includes?(key)
      seen << key

      base = ""
      chained_to = first_attr(action, "chained")
      unless chained_to.empty? || chained_to == "/"
        # A named `Chained('parent')` that resolves to nothing is an
        # incomplete chain fragment, not a standalone route. This happens
        # when CRUD actions live in a Moose role/base controller and chain
        # to a `base`/`object` link defined in a *different* package (the
        # role is composed into many controllers at runtime, so the link
        # only exists after composition). Emitting it would invent a phantom
        # top-level path (`/create`, `/delete`), so skip it instead.
        parent = resolve_chained_parent(action, chained_to, actions_by_name, actions_by_private)
        return unless parent
        parent_path = chained_path(parent, actions_by_name, actions_by_private, seen)
        return if parent_path.nil?
        base = parent_path
      end

      part = if attr_present?(action, "pathpart")
               value = first_attr(action, "pathpart")
               bare_attr_value?(value) ? action.name : value
             else
               action.name
             end
      path = join_url(base, part)
      append_args(path, attr_values(action, "captureargs"), "#{action.name}_capture")
    end

    private def methods_for_action(action : RouteAction, rest_handlers : Hash(String, RouteAction)) : Array(String)
      methods = [] of String

      HTTP_METHOD_ATTRS.each do |attr, method|
        methods << method if attr_present?(action, attr)
      end

      attr_values(action, "method").each do |value|
        methods_from_attr_value(value).each { |method| methods << method }
      end

      if methods.empty? && !rest_handlers.empty?
        methods = rest_handlers.keys.sort!
      end

      methods << "GET" if methods.empty?
      methods.uniq
    end

    private def dispatch_action?(action : RouteAction) : Bool
      attr_present?(action, "path") ||
        attr_present?(action, "local") ||
        attr_present?(action, "global") ||
        attr_present?(action, "index") ||
        attr_present?(action, "chained")
    end

    private def rest_handlers(actions : Array(RouteAction),
                              actions_by_name : Hash(String, RouteAction)) : Hash(String, Hash(String, RouteAction))
      handlers = {} of String => Hash(String, RouteAction)

      actions.each do |action|
        next unless match = action.name.match(/^(.+)_([A-Z]+)$/)
        method = rest_handler_method(match[2])
        next unless method

        base_key = action_key(action.base_path, action.package_name, match[1])
        base_action = actions_by_name[base_key]?
        next unless base_action
        next unless rest_action?(base_action)

        handlers[action_key(base_action)] ||= {} of String => RouteAction
        handlers[action_key(base_action)][method] = action
      end

      handlers
    end

    private def rest_action?(action : RouteAction) : Bool
      attr_values(action, "actionclass").any?(&.downcase.includes?("rest"))
    end

    private def rest_handler_action?(action : RouteAction,
                                     rest_handlers : Hash(String, Hash(String, RouteAction))) : Bool
      key = action_key(action)
      rest_handlers.each_value do |handlers|
        return true if handlers.any? { |_method, handler| action_key(handler) == key }
      end
      false
    end

    private def rest_handler_method(suffix : String) : String?
      normalized = suffix.downcase
      return "OPTIONS" if normalized == "option"
      suffix if HTTP_VERBS.includes?(normalized)
    end

    private def resolve_chained_parent(action : RouteAction,
                                       chained_to : String,
                                       actions_by_name : Hash(String, RouteAction),
                                       actions_by_private : Hash(String, RouteAction)) : RouteAction?
      if chained_to.starts_with?("/")
        return actions_by_private[private_action_key(action.base_path, chained_to)]?
      end

      actions_by_name[action_key(action.base_path, action.package_name, chained_to)]?
    end

    private def append_args(path : String, values : Array(String), name : String) : String
      return path if values.empty?

      count = count_from_arg_spec(values.first)
      if count.nil?
        return join_url(path, ":#{name}")
      end

      result = path
      count.times do |i|
        segment = count == 1 ? ":#{name}" : ":#{name}#{i + 1}"
        result = join_url(result, segment)
      end
      result
    end

    private def count_from_arg_spec(spec : String) : Int32?
      value = spec.strip
      return if bare_attr_value?(value)
      return if value.empty?
      if number = value.to_i?
        return number
      end

      value.split(',').count { |part| !part.strip.empty? }
    end

    private def extract_path_params(path : String) : Array(Param)
      params = [] of Param
      path.scan(/[:*]([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def extract_params_from_body(body : String, method : String) : Array(Param)
      params = [] of Param

      body.scan(/->\s*(?:req|request)\s*->\s*(?:query_params|query_parameters|parameters)\s*->\s*\{?\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        params << Param.new(match[1], "", "query")
      end

      body.scan(/->\s*(?:req|request)\s*->\s*(?:body_params|body_parameters)\s*->\s*\{?\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        params << Param.new(match[1], "", "form")
      end

      body.scan(/->\s*(?:req|request)\s*->\s*(?:body_data|data)\s*->\s*\{?\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        params << Param.new(match[1], "", "json")
      end

      body.scan(/->\s*(?:req|request)\s*->\s*(?:header|headers\s*->\s*header)\s*\(\s*['"]([^'"]+)['"]/) do |match|
        params << Param.new(match[1], "", "header")
      end

      body.scan(/->\s*(?:req|request)\s*->\s*cookies?\s*(?:->\s*\{|\(\s*)\s*['"]?([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        params << Param.new(match[1], "", "cookie")
      end

      body.scan(/->\s*(?:req|request)\s*->\s*param\s*\(\s*['"]([^'"]+)['"]/) do |match|
        param_type = (method == "GET" || method == "HEAD" || method == "OPTIONS") ? "query" : "form"
        params << Param.new(match[1], "", param_type)
      end

      params
    end

    private def methods_from_attr_value(value : String) : Array(String)
      methods = [] of String
      value.scan(/[A-Za-z]+/) do |match|
        normalized = match[0].downcase
        if method = HTTP_METHOD_ATTRS[normalized]?
          methods << method
        end
      end
      methods
    end

    private def push_unique_param(params : Array(Param), param : Param)
      return if param.name.empty?
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def actions_by_name(actions : Array(RouteAction)) : Hash(String, RouteAction)
      map = {} of String => RouteAction
      actions.each { |action| map[action_key(action)] = action }
      map
    end

    private def actions_by_private(actions : Array(RouteAction)) : Hash(String, RouteAction)
      map = {} of String => RouteAction
      actions.each { |action| map[private_action_key(action)] = action }
      map
    end

    private def action_key(action : RouteAction) : String
      action_key(action.base_path, action.package_name, action.name)
    end

    private def action_key(base_path : String, package_name : String, action_name : String) : String
      "#{base_path}\0#{package_name}##{action_name}"
    end

    private def private_action_key(action : RouteAction) : String
      private_action_key(action.base_path, private_path(action))
    end

    private def private_action_key(base_path : String, path : String) : String
      "#{base_path}\0#{path}"
    end

    private def private_path(action : RouteAction) : String
      join_url(namespace_path(action.namespace), action.name)
    end

    private def attr_present?(action : RouteAction, name : String) : Bool
      action.attrs.has_key?(name.downcase)
    end

    private def attr_values(action : RouteAction, name : String) : Array(String)
      action.attrs[name.downcase]? || [] of String
    end

    private def first_attr(action : RouteAction, name : String) : String
      attr_values(action, name).first? || ""
    end

    private def clean_attr_value(value : String) : String
      stripped = value.strip
      if stripped.size >= 2
        first = stripped[0]
        last = stripped[stripped.size - 1]
        if (first == '\'' && last == '\'') || (first == '"' && last == '"')
          return stripped[1, stripped.size - 2]
        end
      end
      stripped
    end

    private def bare_attr_value?(value : String) : Bool
      value == BARE_ATTR_VALUE
    end

    private def controller_namespace(package_name : String, config : ControllerConfig) : String
      if override = config.namespace_override
        return clean_path_prefix(override)
      end

      marker = "::Controller::"
      return "" unless package_name.includes?(marker)

      namespace = package_name.split(marker, 2)[1]
      return "" if namespace == "Root"

      namespace.split("::").map { |part| underscore(part) }.join("/")
    end

    private def path_prefix(namespace : String, config : ControllerConfig) : String
      if override = config.path_override
        return clean_path_prefix(override)
      end

      namespace
    end

    private def namespace_path(namespace : String) : String
      namespace.empty? ? "" : "/#{namespace}"
    end

    private def underscore(name : String) : String
      name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase
    end

    private def clean_path_prefix(value : String) : String
      value.strip.gsub(/^\/+|\/+$/, "")
    end

    private def join_url(prefix : String, leaf : String) : String
      return normalize_path(leaf) if prefix.empty?
      return normalize_path(prefix) if leaf.empty?

      base = prefix.size > 1 ? prefix.chomp('/') : prefix
      tail = leaf.starts_with?('/') ? leaf : "/#{leaf}"
      normalize_path("#{base}#{tail}")
    end

    private def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized.size > 1 && normalized.ends_with?("/") ? normalized.rchop : normalized
    end

    private def catalyst_source_file?(path : String) : Bool
      ext = File.extname(path)
      return false unless ext == ".pl" || ext == ".pm" ||
                          ext == ".psgi" || ext == ".t"
      return false if perl_test_path?(path, ext)
      true
    end

    private def brace_delta(line : String) : Int32
      delta = 0
      line.each_char do |char|
        delta += 1 if char == '{'
        delta -= 1 if char == '}'
      end
      delta
    end

    # Line-aligned copy with strings/comments/regexes blanked (newlines kept),
    # so brace counting ignores braces inside literals. Mirrors dancer2.cr.
    private def code_only_lines(sanitized : Array(String)) : Array(String)
      Noir::PerlCalleeExtractor.strip_non_code(sanitized.join('\n')).lines
    end
  end
end
