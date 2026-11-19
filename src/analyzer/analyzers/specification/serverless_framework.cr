require "../../engines/specification_engine"

module Analyzer::Specification
  class ServerlessFramework < SpecificationEngine
    analyzer_for "serverless_framework"

    METHOD_ANY = "ANY"

    # `${opt:stage, 'dev'}` deploys to its literal fallback unless the CLI
    # names another stage; a variable without one (`${sls:stage}`) names no
    # stage the scan can know, so no prefix is better than a made-up one.
    STAGE_FALLBACK_RE = /\A\$\{.*,\s*['"]([^'"]*)['"]\s*\}+\z/
    # `${file(./functions.yml)}`, optionally `:key` into that file.
    FILE_REF_RE = /\A\$\{file\(([^)]+)\)(?::([\w.-]+))?\}\z/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::SERVERLESS_FRAMEWORK_SPEC) do |path, details|
        content = read_file_content(path)
        if path.ends_with?(".json")
          process_doc(parse_json_lenient(content), details)
        else
          process_doc(YAML.parse(content), details, path)
        end
      end

      @result
    end

    private def process_doc(data : YAML::Any, details : Details, path : String)
      root = data.as_h?
      return unless root

      stage = resolve_stage(string_value(root[YAML::Any.new("provider")]?, "stage"))
      function_maps(root[YAML::Any.new("functions")]?, path).each do |functions|
        functions.each_value do |fn_node|
          fn_h = fn_node.as_h?
          next unless fn_h
          events = fn_h[YAML::Any.new("events")]?.try(&.as_a?) || [] of YAML::Any
          events.each { |event| process_event(event, details, stage) }
        end
      end
    end

    private def process_doc(data : JSON::Any, details : Details)
      root = data.as_h?
      return unless root

      stage = resolve_stage(root["provider"]?.try(&.as_h?).try(&.["stage"]?).try(&.as_s?) || "")
      node = root["functions"]?
      function_maps = node.try(&.as_a?).try(&.compact_map(&.as_h?)) || [node.try(&.as_h?)].compact

      function_maps.each do |functions|
        functions.each_value do |fn_node|
          fn_h = fn_node.as_h?
          next unless fn_h
          events = fn_h["events"]?.try(&.as_a?) || [] of JSON::Any
          events.each { |event| process_event(event, details, stage) }
        end
      end
    end

    private def resolve_stage(stage : String) : String
      return stage unless stage.includes?("${")
      stage.match(STAGE_FALLBACK_RE).try(&.[1]) || ""
    end

    # `functions` as a mapping, a list of mappings, or `${file(...)}` (the
    # whole value or a list item). A referenced file's own `${file()}` items
    # are not followed.
    private def function_maps(node : YAML::Any?, path : String, follow : Bool = true) : Array(Hash(YAML::Any, YAML::Any))
      if h = node.try(&.as_h?)
        [h]
      elsif items = node.try(&.as_a?)
        items.flat_map { |item| function_maps(item, path, follow) }
      elsif follow && (m = node.try(&.as_s?).try(&.match(FILE_REF_RE)))
        target = external_yaml_doc(path, m[1].strip.strip("'\""))
        value = target.try(&.root)
        m[2]?.try(&.split('.').each { |key| value = value.try(&.as_h?).try(&.[YAML::Any.new(key)]?) })
        function_maps(value, path, false)
      else
        [] of Hash(YAML::Any, YAML::Any)
      end
    end

    private def process_event(event : YAML::Any, details : Details, stage : String)
      event_h = event.as_h?
      return unless event_h

      if http_node = event_h[YAML::Any.new("http")]?
        emit_event(http_node, details, stage, "rest")
      end

      if http_api_node = event_h[YAML::Any.new("httpApi")]?
        emit_event(http_api_node, details, stage, "httpapi")
      end
    end

    private def process_event(event : JSON::Any, details : Details, stage : String)
      event_h = event.as_h?
      return unless event_h

      if http_node = event_h["http"]?
        emit_event(http_node, details, stage, "rest")
      end

      if http_api_node = event_h["httpApi"]?
        emit_event(http_api_node, details, stage, "httpapi")
      end
    end

    private def emit_event(node : YAML::Any, details : Details, stage : String, kind : String)
      method, path, authorizer, cors_flag, private_flag = nil, nil, nil, false, false

      if shorthand = node.as_s?
        method, path = parse_shorthand(shorthand)
      elsif h = node.as_h?
        method = string_from(h[YAML::Any.new("method")]?)
        path = string_from(h[YAML::Any.new("path")]?)
        authorizer = authorizer_label(h[YAML::Any.new("authorizer")]?)
        cors_flag = bool_value(h[YAML::Any.new("cors")]?)
        private_flag = bool_value(h[YAML::Any.new("private")]?)
      end

      record_endpoint(method, path, authorizer, cors_flag, private_flag, details, stage, kind)
    end

    private def emit_event(node : JSON::Any, details : Details, stage : String, kind : String)
      method, path, authorizer, cors_flag, private_flag = nil, nil, nil, false, false

      if shorthand = node.as_s?
        method, path = parse_shorthand(shorthand)
      elsif h = node.as_h?
        method = h["method"]?.try(&.as_s?)
        path = h["path"]?.try(&.as_s?)
        if auth = h["authorizer"]?
          authorizer = auth.as_s? || auth.as_h?.try(&.["name"]?).try(&.as_s?) || "custom"
        end
        cors_flag = h["cors"]?.try(&.as_bool?) || false
        private_flag = h["private"]?.try(&.as_bool?) || false
      end

      record_endpoint(method, path, authorizer, cors_flag, private_flag, details, stage, kind)
    end

    private def record_endpoint(method : String?, path : String?, authorizer : String?, cors_flag : Bool, private_flag : Bool, details : Details, stage : String, kind : String)
      return if path.nil? || path.empty?

      resolved_method = (method.nil? || method.empty?) ? METHOD_ANY : method.upcase
      resolved_method = METHOD_ANY if resolved_method == "ANY" || resolved_method == "*"
      full_path = compose_path(stage, path)

      endpoint = Endpoint.new(full_path, resolved_method, details)
      endpoint.add_tag(Tag.new("serverless-event", kind, "serverless_framework_analyzer"))
      endpoint.add_tag(Tag.new("serverless-stage", stage, "serverless_framework_analyzer")) unless stage.empty?
      endpoint.add_tag(Tag.new("serverless-auth", authorizer, "serverless_framework_analyzer")) if authorizer && !authorizer.empty?
      endpoint.add_tag(Tag.new("serverless-cors", "true", "serverless_framework_analyzer")) if cors_flag
      endpoint.add_tag(Tag.new("serverless-private", "true", "serverless_framework_analyzer")) if private_flag
      @result << endpoint
    end

    private def parse_shorthand(value : String) : Tuple(String?, String?)
      parts = value.strip.split(/\s+/, 2)
      return {nil, nil} if parts.size < 2
      {parts[0], parts[1]}
    end

    private def compose_path(stage : String, path : String) : String
      cleaned = path.starts_with?('/') ? path : "/#{path}"
      return cleaned if stage.empty?
      "/#{stage.strip('/')}#{cleaned}"
    end

    private def string_from(node : YAML::Any?) : String?
      node.try(&.as_s?)
    end

    private def string_value(node : YAML::Any?, key : String) : String
      return "" if node.nil?
      h = node.as_h?
      return "" unless h
      value = h[YAML::Any.new(key)]?.try(&.as_s?)
      value || ""
    end

    private def authorizer_label(node : YAML::Any?) : String?
      return if node.nil?
      if str = node.as_s?
        return str
      end
      if h = node.as_h?
        name = h[YAML::Any.new("name")]?.try(&.as_s?)
        name || "custom"
      end
    end

    private def bool_value(node : YAML::Any?) : Bool
      return false if node.nil?
      val = node.raw
      case val
      when Bool   then val
      when String then val.downcase == "true"
      else             false
      end
    end
  end
end
