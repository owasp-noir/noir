require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/adapter"
require "../../../llm/prompt"
require "../../../llm/prompt_overrides"
require "../../../llm/cache"

module Analyzer::AI
  # Unified AI analyzer that uses a provider-agnostic LLM adapter.
  # Supports both OpenAI-compatible APIs and Ollama.
  class Unified < Analyzer
    alias AgentAction = NamedTuple(action: String, args: JSON::Any)

    AGENT_TOOL_MAX_LINES               = 300
    AGENT_TOOL_MAX_MATCHES             = 200
    AGENT_MAX_READ_BYTES               = 10 * 1024
    AGENT_MAX_DEPTH                    = 6
    AGENT_TOOL_RESULT_MAX_CHARS        = 16 * 1024
    AGENT_TOOL_CACHE_MAX_ENTRIES       = 96
    AGENT_CONTEXT_MAX_DYNAMIC_MESSAGES = 16
    AGENT_CONTEXT_MAX_CHARS            = 100 * 1024
    AGENT_DEFAULT_FILE_PATTERN         = "*.{go,py,js,ts,java,rb,php,cs,cr,kt,rs,swift,scala,graphql}"
    VALID_METHODS                      = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]
    VALID_PARAM_TYPES                  = ["query", "json", "form", "header", "cookie", "path"]
    IGNORE_EXTENSIONS                  = [".css", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
                                          ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar",
                                          ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv",
                                          ".log", ".sql", ".bak", ".swp", ".jar"] of String

    @provider : String
    @model : String
    @api_key : String?
    @max_tokens : Int32
    @expanded_base_paths : Array(String)
    @use_agentic : Bool
    @agent_max_steps : Int32
    @native_tool_calling_allowlist : Array(String)?
    @agent_tool_cache : Hash(String, String)
    @agent_tool_cache_order : Array(String)

    def initialize(options : Hash(String, YAML::Any))
      super(options)

      if options.has_key?("ai_provider") && !options["ai_provider"].as_s.empty?
        @provider = options["ai_provider"].as_s
        raw_model = options["ai_model"]?.try(&.as_s) || ""
        @model = if LLM::ACPClient.acp_provider?(@provider)
                   LLM::ACPClient.default_model(@provider, raw_model)
                 else
                   raw_model
                 end
        @api_key = options["ai_key"]?.try(&.as_s)
      elsif options.has_key?("ollama") && !options["ollama"].as_s.empty?
        @provider = options["ollama"].as_s
        @model = options["ollama_model"].as_s
        @api_key = nil
      else
        @provider = "ollama"
        @model = "llama3"
        @api_key = nil
      end

      if options.has_key?("ai_max_token") && !options["ai_max_token"].nil?
        @max_tokens = options["ai_max_token"].as_i
      else
        @max_tokens = LLM.get_max_tokens(@provider, @model)
      end

      @expanded_base_paths = @base_paths.map { |path| File.expand_path(path) }
      @use_agentic = options["ai_agent"]?.try { |val| any_to_bool(val) } || false
      @agent_max_steps = options["ai_agent_max_steps"]?.try(&.as_i) || 20
      @native_tool_calling_allowlist = parse_native_tool_allowlist(options["ai_native_tools_allowlist"]?.try(&.as_s))
      @agent_tool_cache = {} of String => String
      @agent_tool_cache_order = [] of String
    end

    def analyze
      event_sink = if LLM::ACPClient.acp_provider?(@provider)
                     ->(msg : String) { logger.sub "➔ #{msg}" }
                   end
      adapter = LLM::AdapterFactory.for(
        @provider,
        @model,
        @api_key,
        event_sink,
        @native_tool_calling_allowlist
      )
      begin
        logger.info "AI Analysis using #{@provider} with model #{@model} (max tokens: #{@max_tokens})"

        if @use_agentic
          logger.info "AI Agentic workflow is enabled"
          if analyze_with_agentic_workflow(adapter)
            logger.info "AI Agentic workflow completed (#{@result.size} endpoints)"
            Fiber.yield
            return @result
          end
          logger.warning "AI Agentic workflow failed or did not finalize. Falling back to classic AI analysis."
        end

        target_paths = select_target_paths(adapter)
        if target_paths.empty?
          logger.warning "No files selected for AI analysis"
          return @result
        end

        if @max_tokens > 0 && target_paths.size > 5
          analyze_with_bundling(target_paths, adapter)
        else
          target_paths.each { |path| analyze_file(path, adapter) }
        end

        Fiber.yield
        @result
      ensure
        adapter.close
      end
    end

    private def analyze_with_bundling(paths : Array(String), adapter : LLM::Adapter)
      files_to_bundle = prepare_files_for_bundling(paths)
      bundles = LLM.bundle_files(files_to_bundle, @max_tokens)

      process_bundles_concurrently(bundles, adapter)
    end

    private def prepare_files_for_bundling(paths : Array(String)) : Array(Tuple(String, String))
      files = [] of Tuple(String, String)
      paths.each do |path|
        next if File.directory?(path) || File.symlink?(path) || ignore_extensions.includes?(File.extname(path))

        relative_path = get_relative_path(base_path, path)
        content = File.read(path, encoding: "utf-8", invalid: :skip)
        files << {relative_path, content}
      end
      files
    end

    private def process_bundles_concurrently(bundles : Array(Tuple(String, Int32)), adapter : LLM::Adapter)
      channel = Channel(Tuple(String, Int32)).new

      bundles.each_with_index do |bundle, index|
        spawn do
          bundle_content, token_count = bundle
          logger.info "Processing bundle #{index + 1}/#{bundles.size} (#{token_count} tokens)"
          process_bundle(bundle_content, adapter)
          channel.send({bundle_content, token_count})
        end
      end

      bundles.size.times { channel.receive }
    end

    private def process_bundle(bundle_content : String, adapter : LLM::Adapter)
      response = call_llm_with_cache(
        kind: "BUNDLE_ANALYZE",
        system_prompt: LLM::SYSTEM_BUNDLE,
        payload: compose_prompt_payload(LLM::PromptOverrides.bundle_analyze_prompt, bundle_content),
        format: LLM::ANALYZE_FORMAT,
        adapter: adapter
      )

      logger.debug "Bundle analysis response:"
      logger.debug_sub response

      parse_and_store_endpoints(response, "#{base_path}/ai_detected")
    end

    private def select_target_paths(adapter : LLM::Adapter) : Array(String)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")

      if all_paths.size > 10
        logger.debug_sub "AI::Filtering files using LLM"
        filter_paths_with_llm(all_paths, adapter)
      else
        logger.debug_sub "AI::Analyzing all files"
        get_all_source_files
      end
    end

    private def filter_paths_with_llm(all_paths : Array(String), adapter : LLM::Adapter) : Array(String)
      user_payload = all_paths.map { |p| "- #{File.expand_path(p)}" }.join("\n")

      response = call_llm_with_cache(
        kind: "FILTER",
        system_prompt: LLM::SYSTEM_FILTER,
        payload: compose_prompt_payload(LLM::PromptOverrides.filter_prompt, user_payload),
        format: LLM::FILTER_FORMAT,
        adapter: adapter
      )
      logger.debug_sub response

      begin
        filtered = JSON.parse(response.to_s)
        filtered["files"].as_a.map(&.as_s)
      rescue e : Exception
        logger.debug "Error parsing filter response: #{e.message}"
        get_all_source_files
      end
    end

    private def get_all_source_files : Array(String)
      files = [] of String
      base_paths.each do |current_base_path|
        files.concat(Dir.glob("#{escape_glob_path(current_base_path)}/**/*").reject do |p|
          File.directory?(p) || ignore_extensions.includes?(File.extname(p))
        end)
      end
      files
    end

    private def analyze_file(path : String, adapter : LLM::Adapter)
      return if File.directory?(path)
      return if !File.exists?(path) || ignore_extensions.includes?(File.extname(path))

      relative_path = get_relative_path(base_path, path)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        process_file_content(content, relative_path, path, adapter)
      end
    rescue ex : Exception
      logger.debug "Error processing file: #{path}"
      logger.debug "Error: #{ex.message}"
    end

    private def process_file_content(content : String, relative_path : String, path : String, adapter : LLM::Adapter)
      response = call_llm_with_cache(
        kind: "ANALYZE",
        system_prompt: LLM::SYSTEM_ANALYZE,
        payload: compose_prompt_payload(LLM::PromptOverrides.analyze_prompt, content),
        format: LLM::ANALYZE_FORMAT,
        adapter: adapter
      )

      logger.debug "AI response (#{relative_path}):"
      logger.debug_sub response

      parse_and_store_endpoints(response, path)
    end

    private def parse_and_store_endpoints(response : String, default_path : String)
      response_json = JSON.parse(response.to_s)
      response_json["endpoints"].as_a.each do |ep|
        if endpoint = create_endpoint_from_json(ep, default_path)
          @result << endpoint
        end
      end
    rescue e : Exception
      logger.debug "Error parsing response: #{e.message}"
    end

    private def create_endpoint_from_json(ep : JSON::Any, default_path : String) : Endpoint?
      url = extract_endpoint_url(ep)
      return if url.empty?

      method = normalize_http_method(safe_json_string(ep, "method", "GET"))
      path_info = build_path_info(ep, default_path)
      params = extract_params(ep["params"]?)

      details = Details.new(path_info)
      Endpoint.new(url, method, params, details)
    end

    private def create_param_from_json(param : JSON::Any) : Param?
      case param.raw
      when String
        name = param.as_s.strip
        return if name.empty?
        Param.new(name, "", "query")
      when Hash
        name = safe_json_string(param, "name", "").strip
        name = safe_json_string(param, "key", "").strip if name.empty?
        name = safe_json_string(param, "param", "").strip if name.empty?
        return if name.empty?

        param_type = safe_json_string(param, "param_type", "").strip
        param_type = safe_json_string(param, "type", "").strip if param_type.empty?
        value = safe_json_string(param, "value", "")

        Param.new(name, value, normalize_param_type(param_type))
      end
    end

    private def analyze_with_agentic_workflow(adapter : LLM::Adapter) : Bool
      messages = agent_bootstrap_messages
      use_native_tools = adapter.supports_native_tool_calling?
      logger.debug_sub "AI agent mode: #{use_native_tools ? "native tool-calling" : "json action fallback"}"

      @agent_max_steps.times do |step|
        response = if use_native_tools
                     adapter.request_messages_with_tools(messages, LLM::AGENT_TOOLS)
                   else
                     adapter.request_messages(messages, LLM::AGENT_STEP_FORMAT)
                   end
        return false if response.empty?

        logger.debug "AI agent step #{step + 1}:"
        logger.debug_sub response

        append_agent_message(messages, "assistant", response)

        action = parse_agent_action(response)
        unless action
          append_agent_message(messages, "user", "Tool error: invalid action format. Return JSON with action and args.")
          next
        end

        if action[:action] == "finalize"
          logger.verbose "AI agent action: finalize"
          if apply_agent_finalize(action[:args])
            logger.info "AI agent found #{@result.size} potential endpoints" if @is_verbose
            return true
          end

          append_agent_message(messages, "user", "Tool error: finalize must include endpoints array.")
          next
        end

        logger.verbose "AI agent tool call: #{action[:action]}(#{action[:args].to_json})"
        tool_result = run_agent_tool(action[:action], action[:args])
        append_agent_message(messages, "user", "Tool result (#{action[:action]}):\n#{compact_tool_result(tool_result)}")
      end

      false
    rescue ex : Exception
      logger.debug "Agentic workflow failed: #{ex.message}"
      false
    end

    private def agent_bootstrap_messages : Array(Hash(String, String))
      roots = @expanded_base_paths.map { |path| "- #{path}" }.join("\n")
      context = <<-CONTEXT
        Project roots:
        #{roots}

        Start with project exploration and then extract all API endpoints.
        CONTEXT

      [
        {"role" => "system", "content" => LLM::SYSTEM_AGENT},
        {"role" => "user", "content" => compose_prompt_payload(LLM::AGENT_PROMPT, context)},
      ]
    end

    private def parse_agent_action(response : String) : AgentAction?
      parsed = JSON.parse(response)
      action = parsed["action"].as_s
      args = parsed["args"]? || JSON.parse("{}")
      {action: action, args: args}
    rescue
      nil
    end

    private def run_agent_tool(action : String, args : JSON::Any) : String
      cache_key = build_agent_tool_cache_key(action, args)
      if cached = @agent_tool_cache[cache_key]?
        return cached
      end

      result = case action
               when "list_directory"
                 tool_list_directory(args)
               when "read_file"
                 tool_read_file(args)
               when "grep"
                 tool_grep(args)
               when "semantic_search"
                 tool_semantic_search(args)
               else
                 "ERROR: unknown action '#{action}'."
               end
      store_agent_tool_cache(cache_key, result)
      result
    rescue ex : Exception
      "ERROR: #{ex.message}"
    end

    private def build_agent_tool_cache_key(action : String, args : JSON::Any) : String
      "#{action}\n#{args.to_json}"
    end

    private def store_agent_tool_cache(key : String, value : String)
      unless @agent_tool_cache.has_key?(key)
        @agent_tool_cache_order << key
      end
      @agent_tool_cache[key] = value

      overflow = @agent_tool_cache_order.size - AGENT_TOOL_CACHE_MAX_ENTRIES
      return if overflow <= 0

      overflow.times do
        old_key = @agent_tool_cache_order.shift?
        next if old_key.nil?
        @agent_tool_cache.delete(old_key)
      end
    end

    private def compact_tool_result(result : String) : String
      return result if result.size <= AGENT_TOOL_RESULT_MAX_CHARS

      half = AGENT_TOOL_RESULT_MAX_CHARS // 2
      head = result[0, half]? || ""
      tail_start = result.size - half
      tail_start = 0 if tail_start < 0
      tail = result[tail_start, half]? || ""

      <<-TRUNCATED
        NOTE: tool result truncated (#{result.size} chars > #{AGENT_TOOL_RESULT_MAX_CHARS} chars)
        ---HEAD---
        #{head}
        ---TAIL---
        #{tail}
        TRUNCATED
    end

    private def append_agent_message(messages : Array(Hash(String, String)), role : String, content : String)
      messages << {"role" => role, "content" => content}
      prune_agent_messages!(messages)
    end

    private def prune_agent_messages!(messages : Array(Hash(String, String)))
      return if messages.size <= 2

      static_count = 2
      head = messages.first(static_count)
      tail = messages[static_count, messages.size - static_count]

      while tail.size > AGENT_CONTEXT_MAX_DYNAMIC_MESSAGES
        tail.shift
      end

      total_chars = estimate_messages_chars(head) + estimate_messages_chars(tail)
      while total_chars > AGENT_CONTEXT_MAX_CHARS && !tail.empty?
        removed = tail.shift
        total_chars -= estimate_message_chars(removed)
      end

      messages.clear
      messages.concat(head)
      messages.concat(tail)
    end

    private def estimate_messages_chars(messages : Array(Hash(String, String))) : Int32
      messages.sum { |message| estimate_message_chars(message) }
    end

    private def estimate_message_chars(message : Hash(String, String)) : Int32
      (message["role"]? || "").size + (message["content"]? || "").size + 8
    end

    private def apply_agent_finalize(args : JSON::Any) : Bool
      endpoint_json = args["endpoints"]?
      return false if endpoint_json.nil?

      added = 0
      endpoint_json.as_a.each do |ep|
        if endpoint = create_endpoint_from_json(ep, "#{base_path}/ai_detected")
          @result << endpoint
          added += 1
        end
      end

      confidence = safe_json_int(args, "confidence", -1)
      summary = safe_json_string(args, "summary", "")
      logger.info "AI agent finalized #{added} endpoints (confidence=#{confidence})" if confidence >= 0
      logger.verbose "AI agent summary: #{summary}" unless summary.empty?

      true
    rescue ex : Exception
      logger.debug "Error while finalizing agent output: #{ex.message}"
      false
    end

    private def tool_list_directory(args : JSON::Any) : String
      path = safe_json_string(args, "path", ".")
      max_depth = safe_json_int(args, "max_depth", 3)
      max_depth = 1 if max_depth < 1
      max_depth = AGENT_MAX_DEPTH if max_depth > AGENT_MAX_DEPTH

      roots = resolve_agent_roots(path)
      return "ERROR: path '#{path}' is outside base paths or does not exist." if roots.empty?

      lines = [] of String
      roots.each do |root|
        if File.directory?(root)
          lines << "ROOT #{agent_relative_path(root)}"
          walk_directory_tree(root, 0, max_depth, lines)
        else
          lines << "[F] #{agent_relative_path(root)}"
        end
        break if lines.size >= AGENT_TOOL_MAX_LINES
      end

      summarize_lines(lines)
    end

    private def walk_directory_tree(current : String, depth : Int32, max_depth : Int32, lines : Array(String))
      return if depth > max_depth || lines.size >= AGENT_TOOL_MAX_LINES

      entries = Dir.children(current).sort
      entries.each do |entry|
        break if lines.size >= AGENT_TOOL_MAX_LINES

        full_path = File.join(current, entry)
        indent = "  " * depth

        begin
          next if File.symlink?(full_path)

          if File.directory?(full_path)
            lines << "#{indent}[D] #{agent_relative_path(full_path)}/"
            walk_directory_tree(full_path, depth + 1, max_depth, lines) if depth < max_depth
          else
            next if ignore_extensions.includes?(File.extname(full_path))
            lines << "#{indent}[F] #{agent_relative_path(full_path)}"
          end
        rescue ex : Exception
          lines << "#{indent}[E] #{agent_relative_path(full_path)} (#{ex.message})"
        end
      end
    end

    private def tool_read_file(args : JSON::Any) : String
      path = safe_json_string(args, "path", "")
      return "ERROR: path is required." if path.empty?

      resolved = resolve_agent_single_path(path)
      return "ERROR: file '#{path}' is outside base paths or does not exist." if resolved.nil?
      return "ERROR: '#{path}' is a directory. Use list_directory instead." if File.directory?(resolved)

      content = File.read(resolved, encoding: "utf-8", invalid: :skip)
      return "FILE #{agent_relative_path(resolved)}\n#{content}" if content.bytesize <= AGENT_MAX_READ_BYTES

      half = AGENT_MAX_READ_BYTES // 2
      head = content[0, half]? || ""
      tail_start = content.size - half
      tail_start = 0 if tail_start < 0
      tail = content[tail_start, half]? || ""

      <<-TRUNCATED
        FILE #{agent_relative_path(resolved)}
        NOTE: truncated large file (#{content.bytesize} bytes > #{AGENT_MAX_READ_BYTES} bytes)
        ---HEAD---
        #{head}
        ---TAIL---
        #{tail}
        TRUNCATED

    rescue ex : Exception
      "ERROR: failed to read file '#{path}' (#{ex.message})"
    end

    private def tool_grep(args : JSON::Any) : String
      pattern = safe_json_string(args, "pattern", "")
      return "ERROR: pattern is required." if pattern.empty?

      path = safe_json_string(args, "path", ".")
      file_pattern = safe_json_string(args, "file_pattern", AGENT_DEFAULT_FILE_PATTERN)

      collect_grep_results(pattern, path, file_pattern)
    end

    private def tool_semantic_search(args : JSON::Any) : String
      query = safe_json_string(args, "query", "")
      return "ERROR: query is required." if query.empty?

      keywords = query.downcase.split(/[^a-z0-9_]+/).select { |token| token.size >= 3 }.uniq!
      keywords = keywords.first(8)
      return "ERROR: query did not provide useful keywords." if keywords.empty?

      pattern = keywords.map { |keyword| Regex.escape(keyword) }.join("|")
      result = collect_grep_results(pattern, ".", AGENT_DEFAULT_FILE_PATTERN)
      "QUERY_TERMS: #{keywords.join(", ")}\n#{result}"
    end

    private def collect_grep_results(pattern : String, path : String, file_pattern : String) : String
      roots = resolve_agent_roots(path)
      return "ERROR: path '#{path}' is outside base paths or does not exist." if roots.empty?

      regex = Regex.new(pattern)
      matches = [] of String

      roots.each do |root|
        glob = if File.directory?(root)
                 "#{escape_glob_path(root)}/**/#{file_pattern}"
               else
                 escape_glob_path(root)
               end

        Dir.glob(glob).each do |file_path|
          break if matches.size >= AGENT_TOOL_MAX_MATCHES
          next if File.directory?(file_path) || File.symlink?(file_path)
          next if ignore_extensions.includes?(File.extname(file_path))
          next unless path_within_base?(file_path)

          begin
            line_number = 0
            File.open(file_path, "r", encoding: "utf-8", invalid: :skip) do |file|
              file.each_line do |line|
                line_number += 1
                next unless regex_matches_with_timeout?(regex, line)

                snippet = line.strip
                snippet = snippet[0, 220] if snippet.size > 220
                matches << "#{agent_relative_path(file_path)}:#{line_number}: #{snippet}"
                break if matches.size >= AGENT_TOOL_MAX_MATCHES
              end
            end
          rescue ex : Exception
            logger.debug "Error processing file for grep '#{file_path}': #{ex.message}"
          end
        end
      end

      return "NO_MATCH" if matches.empty?
      summarize_lines(matches, AGENT_TOOL_MAX_MATCHES)
    rescue ex : Regex::Error
      "ERROR: invalid regex pattern (#{ex.message})"
    end

    private def compose_prompt_payload(prompt_template : String, content : String) : String
      return prompt_template if content.empty?
      "#{prompt_template.rstrip}\n#{content}"
    end

    private def resolve_agent_roots(path : String) : Array(String)
      normalized = path.strip
      normalized = "." if normalized.empty?

      if normalized == "."
        return @expanded_base_paths.select { |root| File.exists?(root) }
      end

      if normalized.starts_with?("/")
        candidate = File.expand_path(normalized)
        return [] of String unless File.exists?(candidate) && path_within_base?(candidate)
        return [candidate]
      end

      roots = [] of String
      @expanded_base_paths.each do |base|
        candidate = File.expand_path(normalized, base)
        if File.exists?(candidate) && path_within_base?(candidate)
          roots << candidate
        end
      end
      roots.uniq
    end

    private def resolve_agent_single_path(path : String) : String?
      resolve_agent_roots(path).first?
    end

    private def path_within_base?(path : String) : Bool
      expanded = File.expand_path(path)
      @expanded_base_paths.any? do |base|
        expanded == base || expanded.starts_with?("#{base}/")
      end
    end

    private def agent_relative_path(path : String) : String
      expanded = File.expand_path(path)
      @expanded_base_paths.each do |base|
        return "." if expanded == base

        prefix = base.ends_with?("/") ? base : "#{base}/"
        return expanded.sub(prefix, "") if expanded.starts_with?(prefix)
      end
      expanded
    end

    private def summarize_lines(lines : Array(String), limit : Int32 = AGENT_TOOL_MAX_LINES) : String
      return "EMPTY" if lines.empty?
      return lines.join("\n") if lines.size <= limit

      shown = lines[0, limit]
      "#{shown.join("\n")}\n...TRUNCATED #{lines.size - limit} lines"
    end

    private def extract_endpoint_url(ep : JSON::Any) : String
      url = safe_json_string(ep, "url", "").strip
      url = safe_json_string(ep, "path", "").strip if url.empty?

      if !url.empty? && !url.starts_with?("/") && !url.includes?("://")
        "/#{url}"
      else
        url
      end
    end

    private def build_path_info(ep : JSON::Any, default_path : String) : PathInfo
      path = safe_json_string(ep, "file", default_path).strip
      path = default_path if path.empty?
      line = safe_json_int_or_nil(ep, "line")
      PathInfo.new(path, line)
    rescue
      PathInfo.new(default_path)
    end

    private def extract_params(params_json : JSON::Any?) : Array(Param)
      return [] of Param if params_json.nil?

      params = [] of Param
      begin
        params_json.as_a.each do |param|
          if normalized = create_param_from_json(param)
            params << normalized
          end
        end
      rescue ex : Exception
        logger.debug "Error parsing params from LLM response: #{ex.message}"
      end
      params
    end

    private def normalize_http_method(method : String) : String
      normalized = method.upcase
      VALID_METHODS.includes?(normalized) ? normalized : "GET"
    end

    private def normalize_param_type(param_type : String) : String
      normalized = param_type.downcase
      VALID_PARAM_TYPES.includes?(normalized) ? normalized : "query"
    end

    private def safe_json_string(data : JSON::Any, key : String, default : String = "") : String
      value = data[key]?
      return default if value.nil?
      value.as_s
    rescue
      default
    end

    private def safe_json_int(data : JSON::Any, key : String, default : Int32 = 0) : Int32
      value = data[key]?
      return default if value.nil?
      value.as_i
    rescue
      default
    end

    private def safe_json_int_or_nil(data : JSON::Any, key : String) : Int32?
      value = data[key]?
      return if value.nil?
      value.as_i
    rescue
      nil
    end

    private def parse_native_tool_allowlist(raw : String?) : Array(String)?
      return if raw.nil? || raw.strip.empty?
      tokens = raw.split(",").map(&.strip.downcase).reject(&.empty?).uniq!
      tokens.empty? ? nil : tokens
    end

    private def call_llm_with_cache(kind : String, system_prompt : String, payload : String, format : String, adapter : LLM::Adapter) : String
      disk_key = LLM::Cache.key(@provider, @model, kind, format, payload)

      if cached = LLM::Cache.fetch(disk_key)
        return cached
      end

      response = if adapter.supports_context?
                   ctx_key = "#{@provider}:#{@model}:#{kind}"
                   adapter.request_with_context(system_prompt, payload, format, ctx_key)
                 else
                   messages = [{"role" => "system", "content" => system_prompt}, {"role" => "user", "content" => payload}]
                   adapter.request_messages(messages, format)
                 end

      LLM::Cache.store(disk_key, response)
      response
    end

    def ignore_extensions
      IGNORE_EXTENSIONS
    end

    def max_tokens
      @max_tokens
    end
  end
end
