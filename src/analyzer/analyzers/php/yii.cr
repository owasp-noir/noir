require "../../engines/php_engine"

module Analyzer::Php
  class Yii < PhpEngine
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

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        if path.includes?("config") && content.includes?("urlManager")
          endpoints.concat(analyze_url_manager(path, content))
        end

        if path.ends_with?("Controller.php") || content.match(/class\s+\w+Controller\s+extends/)
          endpoints.concat(analyze_controller(path, content))
        end
      end

      endpoints
    end

    # Parse urlManager.rules entries inside Yii2 config files:
    #   "GET /posts" => "post/index"
    #   "POST /posts" => "post/create"
    #   "/posts/<id:\d+>" => "post/view"
    private def analyze_url_manager(path : String, content : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      rules_section = extract_rules_section(content)
      return endpoints if rules_section.nil?

      rules_section.scan(/['"]([^'"]+)['"]\s*=>\s*['"]([^'"]+)['"]/) do |match|
        key = match[1]
        # value = match[2] — the controller target, currently unused

        method, route = split_rule_key(key)
        normalized_path = normalize_route(route)
        params = extract_brace_path_params(normalized_path)

        details = Details.new(PathInfo.new(path))
        endpoints << Endpoint.new(normalized_path, method, params, details)
      end

      endpoints
    end

    # Note: brace counting may be inaccurate if braces appear inside strings or comments.
    # A full PHP parser is out of scope; this is a best-effort implementation.
    private def extract_rules_section(content : String) : String?
      idx = content.index(/["']rules["']\s*=>\s*(?:\[|array\()/)
      return unless idx

      open_char, close_char = detect_rules_brackets(content, idx)
      start = content.index(open_char, idx)
      return unless start

      depth = 1
      pos = start + 1
      while pos < content.size && depth > 0
        case content[pos]
        when open_char
          depth += 1
        when close_char
          depth -= 1
          break if depth == 0
        end
        pos += 1
      end

      return if depth != 0
      content[(start + 1)...pos]
    end

    private def detect_rules_brackets(content : String, idx : Int32) : Tuple(Char, Char)
      bracket_idx = content.index('[', idx)
      paren_idx = content.index("array(", idx)
      if paren_idx && (!bracket_idx || paren_idx < bracket_idx)
        {'(', ')'}
      else
        {'[', ']'}
      end
    end

    private def split_rule_key(key : String) : Tuple(String, String)
      stripped = key.strip
      if match = stripped.match(/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(.+)$/i)
        {match[1].upcase, match[2]}
      else
        {"GET", stripped}
      end
    end

    # Convert Yii2 patterns like `<id:\d+>` or `<slug>` into `{id}` / `{slug}`.
    private def normalize_route(route : String) : String
      normalized = route.gsub(/<(\w+)(?::[^>]+)?>/) { "{#{$1}}" }
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized
    end

    private def analyze_controller(path : String, content : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      controller_name = extract_controller_name(path, content)
      return endpoints if controller_name.empty?

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
      content.scan(/(?:^|[\s;{}])(?:public\s+)?function\s+action([A-Z]\w*)\s*\(([^)]*)\)\s*\{/) do |match|
        action_name = match[1]
        param_sig = match[2]
        full_match = match[0]

        method_start = content.index(full_match, offset)
        next unless method_start
        offset = method_start + full_match.size

        route_action = camel_to_dashed(action_name)
        route_path = "/#{controller_name}/#{route_action}"

        params = extract_action_signature_params(param_sig)

        method_body = extract_method_body(content, method_start + full_match.size - 1)
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
          endpoints << Endpoint.new(route_path, method, params, details)
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

    # Brace-count from an opening `{` to isolate the matching method body;
    # prevents param/method leakage across adjacent action methods.
    # Note: brace counting may be inaccurate if braces appear inside strings or comments.
    # A full PHP parser is out of scope; this is a best-effort implementation.
    private def extract_method_body(content : String, brace_start : Int32) : String
      return "" unless brace_start < content.size && content[brace_start] == '{'

      depth = 1
      pos = brace_start + 1
      while pos < content.size && depth > 0
        case content[pos]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          break if depth == 0
        end
        pos += 1
      end

      return "" if depth != 0 || pos <= brace_start + 1
      content[(brace_start + 1)...pos]
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
