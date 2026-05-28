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
      property namespace_override, path_override

      def initialize(@namespace_override : String? = nil,
                     @path_override : String? = nil)
      end
    end

    private struct RouteAction
      property name, package_name, namespace, path_prefix, attrs, body, file_path, line

      def initialize(@name : String,
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
      actions_mutex = Mutex.new
      parallel_file_scan do |path|
        next unless catalyst_source_file?(path)

        file_actions = collect_actions(read_file_content(path), path)
        actions_mutex.synchronize { actions.concat(file_actions) }
      end

      @result.concat(analyze_actions(actions))
      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless catalyst_source_file?(path)

      content = read_file_content(path)
      analyze_content(content, path)
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      actions = collect_actions(content, file_path)
      analyze_actions(actions)
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

    private def collect_actions(content : String, file_path : String) : Array(RouteAction)
      raw_lines = content.lines
      lines = sanitize_perl_lines(raw_lines)
      package_configs = collect_controller_configs(lines)
      actions = [] of RouteAction
      package_name = ""
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
            brace_depth += brace_delta(body_line)
            opened = true if body_line.includes?("{")
            break if opened && brace_depth <= 0
            body_index += 1
          end
          index = body_index
        end

        attrs = parse_attrs(declaration)
        config = package_configs[package_name]? || ControllerConfig.new
        namespace = controller_namespace(package_name, config)
        actions << RouteAction.new(
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
      configs = {} of String => ControllerConfig
      package_name = ""
      index = 0

      while index < lines.size
        line = lines[index]
        if package_match = line.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_:]*)\s*;/)
          package_name = package_match[1]
        end

        unless line.includes?("__PACKAGE__->config")
          index += 1
          next
        end

        statement = line
        while !statement.includes?(";") && index + 1 < lines.size
          index += 1
          statement += " " + lines[index].strip
        end

        namespace_override = config_value(statement, "namespace")
        path_override = config_value(statement, "path")
        if namespace_override || path_override
          configs[package_name] = ControllerConfig.new(namespace_override, path_override)
        end

        index += 1
      end

      configs
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
        if parent = resolve_chained_parent(action, chained_to, actions_by_name, actions_by_private)
          parent_path = chained_path(parent, actions_by_name, actions_by_private, seen)
          base = parent_path || ""
        end
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

        base_key = "#{action.package_name}##{match[1]}"
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
        return actions_by_private[chained_to]?
      end

      actions_by_name["#{action.package_name}##{chained_to}"]?
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
      actions.each { |action| map[private_path(action)] = action }
      map
    end

    private def action_key(action : RouteAction) : String
      "#{action.package_name}##{action.name}"
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

    private def perl_test_path?(path : String, ext : String) : Bool
      return true if ext == ".t"
      return true if path.includes?("/t/")
      false
    end

    private def catalyst_source_file?(path : String) : Bool
      ext = File.extname(path)
      return false unless ext == ".pl" || ext == ".pm" ||
                          ext == ".psgi" || ext == ".t"
      return false if perl_test_path?(path, ext)
      true
    end

    private def sanitize_perl_lines(lines : Array(String)) : Array(String)
      in_pod = false
      ended = false
      lines.map do |line|
        stripped = line.lstrip
        if ended
          ""
        elsif stripped.starts_with?("__END__") || stripped.starts_with?("__DATA__")
          ended = true
          ""
        elsif in_pod
          if stripped.starts_with?("=cut")
            in_pod = false
          end
          ""
        elsif stripped.size >= 2 && stripped[0] == '=' && stripped[1].ascii_letter?
          in_pod = true
          ""
        else
          line
        end
      end
    end

    private def brace_delta(line : String) : Int32
      delta = 0
      line.each_char do |char|
        delta += 1 if char == '{'
        delta -= 1 if char == '}'
      end
      delta
    end
  end
end
