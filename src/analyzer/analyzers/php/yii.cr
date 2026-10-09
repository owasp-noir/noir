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

    # A rule key that starts with a verb list, split the way
    # yii\web\UrlManager::buildRules does: case-sensitive verbs, commas with no
    # spaces, then whitespace and a pattern. Anything else (`'get'`, `'POST'`)
    # is a plain pattern.
    RULE_VERB_RE = /\A((?:(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS),)*(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS))\s+(.+)\z/
    # yii\rest\UrlRule pattern keys, where the pattern part is optional
    # (`'POST' => 'create'`).
    REST_VERB_RE = /\A((?:(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS),)*(?:GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS))(?:\s+(.*))?\z/
    RULES_KEY_RE = /["']rules["']\s*=>\s*(?:\[|array\s*\()/

    # yii\rest\UrlRule's default `patterns`. A verb-less entry matches any
    # verb; it serves the `options` action.
    REST_RULE_PATTERNS = {
      "PUT,PATCH {id}" => "update",
      "DELETE {id}"    => "delete",
      "GET,HEAD {id}"  => "view",
      "POST"           => "create",
      "GET,HEAD"       => "index",
      "{id}"           => "options",
      ""               => "options",
    }

    # One top-level entry of a PHP array literal: its string key (nil for a
    # list entry) and its value — a string literal (`string`), a nested
    # array's interior (`inner`, lexer char range), or other scalar text
    # (`raw`, e.g. `false`).
    private record ArrayEntry, key : String?, string : String?, inner : Range(Int32, Int32)?, raw : String?

    # Parse urlManager.rules entries inside Yii2 config files:
    #   "GET /posts" => "post/index"
    #   "GET,HEAD /posts" => "post/index"
    #   "/posts/<id:\d+>" => "post/view"
    #   ['pattern' => 'feed/<slug>', 'route' => 'feed/view', 'verb' => 'GET']
    #   ['class' => 'yii\rest\UrlRule', 'controller' => 'user']
    #   ['class' => 'yii\web\GroupUrlRule', 'prefix' => 'admin', 'rules' => [...]]
    #
    # Only the rules array's own entries are rules: the `'k' => 'v'` pairs
    # inside an array-style rule are its options, not routes.
    private def analyze_url_manager(path : String, content : String) : Array(Endpoint)
      key = content.match(RULES_KEY_RE)
      return [] of Endpoint unless key

      lexer = Noir::PhpLexer.new(content)
      open = key.end(0) - 1
      close = lexer.matching_delimiter(open)
      return [] of Endpoint unless close

      rules_endpoints(lexer, (open + 1)...close, "", Details.new(PathInfo.new(path)), 0)
    end

    # GroupUrlRule nesting beyond this is not followed.
    MAX_RULE_GROUP_DEPTH = 16

    private def rules_endpoints(lexer : Noir::PhpLexer, range : Range(Int32, Int32), prefix : String,
                                details : Details, depth : Int32) : Array(Endpoint)
      endpoints = [] of Endpoint
      array_entries(lexer, range).each do |entry|
        if (key = entry.key) && (route = entry.string)
          next if route.empty?
          methods, pattern = split_rule_key(key)
          endpoints.concat(rule_endpoints(methods, join_rule_path(prefix, pattern), details))
        elsif inner = entry.inner
          # An array value is a rule config whatever its key: UrlManager
          # only reads a string key as the pattern of a string rule.
          endpoints.concat(array_rule_endpoints(lexer, inner, prefix, details, depth))
        end
      end
      endpoints
    end

    private def array_rule_endpoints(lexer : Noir::PhpLexer, range : Range(Int32, Int32), prefix : String,
                                     details : Details, depth : Int32) : Array(Endpoint)
      options = {} of String => ArrayEntry
      array_entries(lexer, range).each { |entry| entry.key.try { |k| options[k] ||= entry } }

      if rules = options["rules"]?.try(&.inner)
        # yii\web\GroupUrlRule: `prefix` leads every pattern declared inside.
        if depth >= MAX_RULE_GROUP_DEPTH
          details.code_paths.first?.try { |code_path| Noir::SkippedFiles.record(tech, code_path.path, "GroupUrlRule nesting deeper than #{MAX_RULE_GROUP_DEPTH} levels") }
          return [] of Endpoint
        end
        group_prefix = join_rule_path(prefix, options["prefix"]?.try(&.string) || "")
        rules_endpoints(lexer, rules, group_prefix, details, depth + 1)
      elsif options.has_key?("controller")
        rest_rule_endpoints(lexer, range, options, details)
      elsif pattern = options["pattern"]?.try(&.string)
        verbs = option_strings(lexer, options["verb"]?).map(&.upcase)
        verbs = ["GET"] if verbs.empty?
        rule_endpoints(verbs, join_rule_path(prefix, pattern), details)
      else
        [] of Endpoint
      end
    end

    # yii\rest\UrlRule: every controller gets the default `patterns` plus its
    # `extraPatterns`, filtered by `only`/`except`. `'controller' => 'user'`
    # or `['user', 'v1/post']` serves the pluralized name unless
    # `'pluralize' => false`; `['u' => 'user']` serves the key as given.
    private def rest_rule_endpoints(lexer : Noir::PhpLexer, range : Range(Int32, Int32),
                                    options : Hash(String, ArrayEntry), details : Details) : Array(Endpoint)
      controller = options["controller"]
      plural = !{"false", "0"}.includes?(options["pluralize"]?.try(&.raw).try(&.downcase))
      url_names = if name = controller.string
                    [plural ? pluralize(name) : name]
                  elsif inner = controller.inner
                    array_entries(lexer, inner).compact_map do |entry|
                      next unless name = entry.string
                      entry.key || (plural ? pluralize(name) : name)
                    end
                  else
                    [] of String
                  end

      # `extraPatterns + patterns`, PHP array union: an extra pattern wins a
      # shared key. A rule's own `patterns` replaces the defaults.
      patterns = {} of String => String
      {"extraPatterns", "patterns"}.each do |option|
        next unless inner = options[option]?.try(&.inner)
        array_entries(lexer, inner).each do |entry|
          key, action = entry.key, entry.string
          patterns[key] = action if key && action && !patterns.has_key?(key)
        end
      end
      unless options.has_key?("patterns")
        REST_RULE_PATTERNS.each { |key, action| patterns[key] = action unless patterns.has_key?(key) }
      end

      rule_text = lexer.source(range)
      prefix = options["prefix"]?.try(&.string) || ""
      endpoints = [] of Endpoint
      url_names.each do |url_name|
        base = join_rule_path(prefix, url_name)
        patterns.each do |key, action|
          next unless resource_action_allowed?(rule_text, action)
          if match = key.match(REST_VERB_RE)
            endpoints.concat(rule_endpoints(match[1].split(','), join_rule_path(base, match[2]? || ""), details))
          else
            # A verb-less pattern answers any verb: report the defaults'
            # `options` action as OPTIONS, anything else as GET.
            verbs = action == "options" ? ["OPTIONS"] : ["GET"]
            endpoints.concat(rule_endpoints(verbs, join_rule_path(base, key), details))
          end
        end
      end
      endpoints
    end

    # Top-level entries of the PHP array whose interior is `range`. Walks the
    # lexer's masked text once: strings come from its spans, nested arrays
    # (`[...]` / `array(...)`) are skipped whole via `matching_delimiter`.
    private def array_entries(lexer : Noir::PhpLexer, range : Range(Int32, Int32)) : Array(ArrayEntry)
      entries = [] of ArrayEntry
      spans = lexer.spans
      span_index = spans.bsearch_index { |(_, s, _)| s >= range.begin } || spans.size
      key = nil
      value_start = nil
      i = range.begin
      stop = range.end
      while i < stop
        while span_index < spans.size && spans[span_index][1] < i
          span_index += 1
        end
        span = spans[span_index]?
        if span && span[1] == i
          kind, s, e = span
          if kind == :string
            text = lexer.source((s + 1)...(e - 1))
            j = e
            while j < stop && lexer.masked[j].whitespace?
              j += 1
            end
            if key.nil? && lexer.masked[j]? == '=' && lexer.masked[j + 1]? == '>'
              key = text
              i = j + 2
              value_start = i
            else
              entries << ArrayEntry.new(key, text, nil, nil)
              key = nil
              value_start = nil
              i = e
            end
          else
            i = e
          end
          next
        end

        c = lexer.masked[i]
        if c == '[' || c == '('
          close = lexer.matching_delimiter(i) || stop
          entries << ArrayEntry.new(key, nil, (i + 1)...close, nil)
          key = nil
          value_start = nil
          i = close + 1
          next
        elsif c == ','
          if (k = key) && (from = value_start)
            entries << ArrayEntry.new(k, nil, nil, lexer.source(from...i).strip)
          end
          key = nil
          value_start = nil
        end
        i += 1
      end
      if (k = key) && (from = value_start)
        entries << ArrayEntry.new(k, nil, nil, lexer.source(from...stop).strip)
      end
      entries
    end

    # String values of an option given as one string or a list of them.
    private def option_strings(lexer : Noir::PhpLexer, entry : ArrayEntry?) : Array(String)
      return [] of String unless entry
      if value = entry.string
        [value]
      elsif inner = entry.inner
        array_entries(lexer, inner).compact_map(&.string)
      else
        [] of String
      end
    end

    private def join_rule_path(prefix : String, pattern : String) : String
      return pattern if prefix.empty?
      return prefix if pattern.empty?
      "#{prefix.rstrip('/')}/#{pattern.lstrip('/')}"
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
      if match = key.match(RULE_VERB_RE)
        {match[1].split(','), match[2]}
      else
        {["GET"], key.strip}
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
