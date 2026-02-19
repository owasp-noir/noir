require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/adapter"
require "../../../llm/prompt"
require "../../../llm/cache"

module Analyzer::AI
  # Unified AI analyzer that uses a provider-agnostic LLM adapter.
  # Supports both OpenAI-compatible APIs and Ollama.
  class Unified < Analyzer
    @provider : String
    @model : String
    @api_key : String?
    @max_tokens : Int32

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
    end

    def analyze
      event_sink = if LLM::ACPClient.acp_provider?(@provider)
                     ->(msg : String) { logger.sub "➔ #{msg}" }
                   end
      adapter = LLM::AdapterFactory.for(@provider, @model, @api_key, event_sink)
      begin
        target_paths = select_target_paths(adapter)
        if target_paths.empty?
          logger.warning "No files selected for AI analysis"
          return @result
        end

        logger.info "AI Analysis using #{@provider} with model #{@model} (max tokens: #{@max_tokens})"

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
        payload: bundle_content,
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
        payload: user_payload,
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
        payload: content,
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
        endpoint = create_endpoint_from_json(ep, default_path)
        @result << endpoint
      end
    rescue e : Exception
      logger.debug "Error parsing response: #{e.message}"
    end

    private def create_endpoint_from_json(ep : JSON::Any, default_path : String) : Endpoint
      url = ep["url"].as_s
      method = ep["method"].as_s

      path_info = if ep.as_h.has_key?("file") && !ep["file"].as_s.empty?
                    PathInfo.new(ep["file"].as_s)
                  else
                    PathInfo.new(default_path)
                  end

      params = ep["params"].as_a.map do |param|
        create_param_from_json(param)
      end

      details = Details.new(path_info)
      Endpoint.new(url, method, params, details)
    end

    private def create_param_from_json(param : JSON::Any) : Param
      p = param.as_h
      name = p["name"].as_s
      param_type = if p.has_key?("param_type")
                     p["param_type"].as_s
                   elsif p.has_key?("type")
                     p["type"].as_s
                   else
                     ""
                   end
      value = p["value"]? ? p["value"].as_s : ""
      Param.new(name, value, param_type)
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
      [".css", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
       ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar",
       ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv",
       ".log", ".sql", ".bak", ".swp", ".jar"]
    end

    def max_tokens
      @max_tokens
    end
  end
end
