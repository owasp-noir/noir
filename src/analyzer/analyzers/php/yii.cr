require "../../engines/php_engine"

module Analyzer::Php
  class Yii < PhpEngine
    analyzer_for "php_yii"

    # Standard REST verbs auto-exposed by yii\rest\ActiveController.
    REST_ACTIONS = {
      "index"   => ["GET"],
      "view"    => ["GET"],
      "create"  => ["POST"],
      "update"  => ["PUT", "PATCH"],
      "delete"  => ["DELETE"],
      "options" => ["OPTIONS"],
    }

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      return endpoints unless path.ends_with?(".php")
      include_callee = callees_needed?

      content = read_file_content(path)

      url_manager = path.includes?("config") && content.includes?("urlManager")
      controller = path.ends_with?("Controller.php") ||
                   (content.includes?("Controller") && content.includes?("extends") &&
                    !!content.match(/class\s+\w+Controller\s+extends/))
      return endpoints unless url_manager || controller

      content = php_code(content)
      endpoints.concat(analyze_url_manager(path, content)) if url_manager
      endpoints.concat(analyze_controller(path, content, include_callee)) if controller

      endpoints
    end

    # A rule key's verb list: `GET /posts`, `GET,HEAD posts`, or a bare
    # `POST` (pattern ''), as yii\web\UrlRule::init splits it.
    RULE_VERB_RE  = /^((?:(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS)\s*,\s*)*(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS))(?:\s+(.*))?$/i
    RULES_KEY_RE  = /["']rules["']\s*=>\s*(?:\[|array\s*\()/
    RULE_PAIR_RE  = /['"]([^'"]+)['"]\s*=>\s*['"]([^'"]+)['"]/
    RULE_OPTIONS  = /['"](pattern|verb|controller|prefix)['"]\s*=>\s*(?:['"]([^'"]*)['"]|(?:\[|array\s*\()([^\])]*))/
    QUOTED_STRING = /['"]([^'"]+)['"]/

    # yii\rest\UrlRule's default `patterns`, `{id}` standing for
    # `<id:\d[\d,]*>`. A verb-less entry matches any verb; it serves the
    # `options` action.
    REST_RULE_PATTERNS = [
      {["PUT", "PATCH"], "/{id}"},
      {["DELETE"], "/{id}"},
      {["GET", "HEAD"], "/{id}"},
      {["POST"], ""},
      {["GET", "HEAD"], ""},
      {["OPTIONS"], "/{id}"},
      {["OPTIONS"], ""},
    ]

    # Parse urlManager.rules entries inside Yii2 config files:
    #   "GET /posts" => "post/index"
    #   "GET,HEAD /posts" => "post/index"
    #   "/posts/<id:\d+>" => "post/view"
    #   ['pattern' => 'feed/<slug>', 'route' => 'feed/view', 'verb' => 'GET']
    #   ['class' => 'yii\rest\UrlRule', 'controller' => 'user']
    #
    # Only the rules array's own entries are rules: the `'k' => 'v'` pairs
    # inside an array-style rule are its options, not routes.
    private def analyze_url_manager(path : String, content : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      key = content.match(RULES_KEY_RE)
      return endpoints unless key

      lexer = Noir::PhpLexer.new(content)
      open = key.end(0) - 1
      close = lexer.matching_delimiter(open)
      return endpoints unless close

      details = Details.new(PathInfo.new(path))
      segment_start = open + 1
      i = segment_start
      while i < close
        c = lexer.masked[i]
        if c == '[' || c == '('
          nested_close = lexer.matching_delimiter(i) || close
          endpoints.concat(string_rule_endpoints(lexer.source(segment_start...i), details))
          endpoints.concat(array_rule_endpoints(lexer.source((i + 1)...nested_close), details))
          i = nested_close + 1
          segment_start = i
        else
          i += 1
        end
      end
      endpoints.concat(string_rule_endpoints(lexer.source(segment_start...close), details)) if segment_start < close

      endpoints
    end

    private def string_rule_endpoints(segment : String, details : Details) : Array(Endpoint)
      endpoints = [] of Endpoint
      segment.scan(RULE_PAIR_RE) do |match|
        methods, route = split_rule_key(match[1])
        endpoints.concat(rule_endpoints(methods, route, details))
      end
      endpoints
    end

    private def array_rule_endpoints(rule : String, details : Details) : Array(Endpoint)
      options = Hash(String, Array(String)).new
      rule.scan(RULE_OPTIONS) do |m|
        next if options.has_key?(m[1])
        options[m[1]] = if single = m[2]?
                          [single]
                        else
                          m[3].scan(QUOTED_STRING).map(&.[1])
                        end
      end

      if controllers = options["controller"]?
        rest_rule_endpoints(rule, controllers, options["prefix"]?.try(&.first?) || "", details)
      elsif pattern = options["pattern"]?.try(&.first?)
        methods = options["verb"]?.try(&.map(&.upcase)) || [] of String
        methods = ["GET"] if methods.empty?
        rule_endpoints(methods, pattern, details)
      else
        [] of Endpoint
      end
    end

    # `'controller' => 'user'` or `['user', 'v1/post']` serves the pluralized
    # name; `['u' => 'user']` serves the key as given.
    private def rest_rule_endpoints(rule : String, controllers : Array(String), prefix : String, details : Details) : Array(Endpoint)
      url_names = [] of String
      if list = rule.match(/['"]controller['"]\s*=>\s*(?:\[|array\s*\()([^\])]*)/)
        list[1].scan(/['"]([^'"]+)['"](?:\s*=>\s*['"][^'"]+['"])?/) do |m|
          url_names << (m[0].includes?("=>") ? m[1] : pluralize(m[1]))
        end
      else
        url_names = controllers.map { |name| pluralize(name) }
      end

      endpoints = [] of Endpoint
      url_names.each do |name|
        base = prefix.empty? ? name : "#{prefix.strip('/')}/#{name}"
        REST_RULE_PATTERNS.each do |methods, suffix|
          endpoints.concat(rule_endpoints(methods, base + suffix, details))
        end
      end
      endpoints
    end

    private def rule_endpoints(methods : Array(String), route : String, details : Details) : Array(Endpoint)
      normalized_path = normalize_route(route)
      params = extract_brace_path_params(normalized_path)
      methods.map { |method| Endpoint.new(normalized_path, method, params, details.dup) }
    end

    # ponytail: regular English plurals only, unlike yii\helpers\Inflector's
    # irregular table (person → people).
    private def pluralize(name : String) : String
      case name
      when /[^aeiou]y\z/       then name[0...-1] + "ies"
      when /(?:s|x|z|ch|sh)\z/ then name + "es"
      else                          name + "s"
      end
    end

    private def split_rule_key(key : String) : Tuple(Array(String), String)
      stripped = key.strip
      if match = stripped.match(RULE_VERB_RE)
        {match[1].split(',').map(&.strip.upcase), match[2]? || ""}
      else
        {["GET"], stripped}
      end
    end

    # Convert Yii2 patterns like `<id:\d+>` or `<slug>` into `{id}` / `{slug}`.
    private def normalize_route(route : String) : String
      normalized = route.gsub(/<(\w+)(?::[^>]+)?>/) { "{#{$1}}" }
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized
    end

    # A Yii controller is a console (CLI) controller when it extends
    # any class under `yii\console\Controller` — directly via
    # `extends \yii\console\Controller` / `extends yii\console\Controller`,
    # or via a `use yii\console\Controller` import paired with
    # `extends Controller`. Production code uses the same hierarchy
    # for built-in `migrate`, `fixture`, `cache`, etc. commands.
    private def console_controller?(content : String) : Bool
      return true if content.matches?(/extends\s+\\?yii\\console\\Controller/)
      return true if content.includes?("yii\\console\\Controller") &&
                     content.matches?(/extends\s+(?:Console)?Controller\b/)
      false
    end

    private def analyze_controller(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      controller_name = extract_controller_name(path, content)
      return endpoints if controller_name.empty?

      # Skip console (CLI) controllers — they expose CLI commands
      # like `migrate/up`, `fixture/load`, never HTTP routes. The
      # framework repo's `framework/console/controllers/*` parks 25
      # phantom HTTP endpoints when they're really `yii migrate up`
      # style invocations.
      return endpoints if console_controller?(content)

      # Detect REST (ActiveController / rest\Controller) — exposes standard CRUD verbs.
      # Match both fully-qualified names and `use`-imported short names.
      is_rest = content.match(/extends\s+\\?yii\\rest\\(?:Active)?Controller/) ||
                (content.match(/use\s+yii\\rest\\(?:Active)?Controller\s*;/) &&
                 content.match(/extends\s+(?:Active)?Controller\b/))
      if is_rest
        REST_ACTIONS.each do |action, methods|
          route_path = "/#{controller_name}/#{action}"
          methods.each do |method|
            details = Details.new(PathInfo.new(path))
            endpoints << Endpoint.new(route_path, method, [] of Param, details)
          end
        end
      end

      # Scan action*() methods — the standard Yii2 controller action pattern.
      offset = 0
      # Only public methods are actions; Yii never routes to a protected or
      # private `actionX()`.
      content.scan(/(?:^|[\s;{}])((?:(?:public|protected|private|static|final|abstract)\s+)*)function\s+action([A-Z]\w*)\s*\(([^)]*)\)\s*\{/) do |match|
        next if match[1].matches?(/\b(?:protected|private)\b/)
        action_name = match[2]
        param_sig = match[3]
        full_match = match[0]

        method_start = content.index(full_match, offset)
        next unless method_start
        offset = method_start + full_match.size

        route_action = camel_to_dashed(action_name)
        route_path = "/#{controller_name}/#{route_action}"

        params = extract_action_signature_params(param_sig)

        method_body_info = extract_php_method_body_after(content, method_start)
        method_body = method_body_info ? method_body_info[0] : ""
        body_params = extract_request_params(method_body)

        seen = Set(String).new(params.map(&.name))
        body_params.each do |param|
          next if seen.includes?(param.name)
          params << param
          seen.add(param.name)
        end

        details = Details.new(PathInfo.new(path))
        methods = infer_methods_from_body(method_body)

        methods.each do |method|
          endpoint = Endpoint.new(route_path, method, params, details)
          attach_method_callees(endpoint, method_body_info, path) if include_callee
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def extract_controller_name(path : String, content : String) : String
      if match = content.match(/class\s+(\w+)Controller\s+extends/)
        return camel_to_dashed(match[1])
      end

      basename = File.basename(path, ".php")
      if basename.ends_with?("Controller")
        return camel_to_dashed(basename[0...-"Controller".size])
      end

      ""
    end

    # Yii2 maps CamelCase class/action names to dashed URL segments:
    # `UserProfileController` -> `user-profile`, `actionViewAll` -> `view-all`.
    private def camel_to_dashed(name : String) : String
      return "" if name.empty?
      result = String.build do |io|
        name.each_char_with_index do |char, i|
          if char.ascii_uppercase? && i > 0
            io << '-'
          end
          io << char.downcase
        end
      end
      result
    end

    private def extract_action_signature_params(signature : String) : Array(Param)
      params = [] of Param
      return params if signature.strip.empty?

      signature.split(',').each do |part|
        cleaned = part.strip
        next if cleaned.empty?
        if match = cleaned.match(/\$(\w+)/)
          params << Param.new(match[1], "", "query")
        end
      end
      params
    end

    private def extract_request_params(context : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      # Yii::$app->request->get("name") -> query
      context.scan(/Yii::\$app->request->get\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "query")
        seen.add(name)
      end

      # Yii::$app->request->post("name") -> form
      context.scan(/Yii::\$app->request->post\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "form")
        seen.add(name)
      end

      # $request->get("name") / post("name") inside controllers
      context.scan(/\$request->get\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "query")
        seen.add(name)
      end

      context.scan(/\$request->post\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "form")
        seen.add(name)
      end

      # Yii::$app->request->headers->get("X-Header")
      context.scan(/Yii::\$app->request->headers->get\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "header")
        seen.add(name)
      end

      # Yii::$app->request->cookies->get("name")
      context.scan(/Yii::\$app->request->cookies->get\s*\(\s*['"]([^'"]+)['"]/) do |match|
        name = match[1]
        next if seen.includes?(name)
        params << Param.new(name, "", "cookie")
        seen.add(name)
      end

      params
    end

    # Default a Yii2 action to GET. Bump to GET+POST when the body touches post/form data
    # (typical "handles both" pattern) so we don't miss form submissions.
    private def infer_methods_from_body(context : String) : Array(String)
      touches_post = context.includes?("->post(") ||
                     context.includes?("isPost") ||
                     context.includes?("request->post") ||
                     context.includes?("$_POST")
      touches_post ? ["GET", "POST"] : ["GET"]
    end
  end
end
