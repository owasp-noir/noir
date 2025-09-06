require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/general/client"
require "../../../llm/prompt"
require "../../../llm/cache"

module Analyzer::AI
  class General < Analyzer
    @llm_url : String
    @model : String
    @api_key : String?
    @max_tokens : Int32

    def initialize(options : Hash(String, YAML::Any))
      super(options)
      @llm_url = options["ai_provider"].as_s
      @model = options["ai_model"].as_s
      @api_key = options["ai_key"].as_s
      if options.has_key?("ai_max_token") && !options["ai_max_token"].nil?
        @max_tokens = options["ai_max_token"].as_i
      else
        @max_tokens = LLM.get_max_tokens(@llm_url, @model)
      end
    end

    def analyze
      client = LLM::General.new(@llm_url, @model, @api_key)
      target_paths = select_target_paths(client)

      if target_paths.empty?
        logger.warning "No files selected for AI analysis"
        return @result
      end

      # Use the bundling approach if we have a token limit
      logger.info "AI Analysis using #{@llm_url} with model #{@model} (max tokens: #{@max_tokens})"

      if @max_tokens > 0 && target_paths.size > 5
        analyze_with_bundling(target_paths, client)
      else
        target_paths.each { |path| analyze_file(path, client) }
      end

      Fiber.yield
      @result
    end

    private def analyze_with_bundling(paths : Array(String), client : LLM::General)
      files_to_bundle = [] of Tuple(String, String)
      paths.each do |path|
        next if File.directory?(path) || File.symlink?(path) || ignore_extensions.includes?(File.extname(path))
        relative_path = get_relative_path(base_path, path)
        content = File.read(path, encoding: "utf-8", invalid: :skip)
        files_to_bundle << {relative_path, content}
      end

      bundles = LLM.bundle_files(files_to_bundle, @max_tokens)
      channel = Channel(Tuple(String, Int32)).new

      bundles.each_with_index do |bundle, index|
        spawn do
          bundle_content, token_count = bundle
          logger.info "Processing bundle #{index + 1}/#{bundles.size} (#{token_count} tokens)"
          process_bundle(bundle_content, client)
          channel.send({bundle_content, token_count})
        end
      end

      bundles.size.times { channel.receive }
    end

    private def process_bundle(bundle_content : String, client : LLM::General)
      messages = [{"role" => "system", "content" => LLM::SYSTEM_BUNDLE}, {"role" => "user", "content" => bundle_content}]
      key = LLM::Cache.key(@llm_url, @model, "BUNDLE_ANALYZE", LLM::ANALYZE_FORMAT, bundle_content)
      response = if cached = LLM::Cache.fetch(key)
                   cached
                 else
                   r = client.request_messages(messages, LLM::ANALYZE_FORMAT)
                   LLM::Cache.store(key, r.to_s)
                   r
                 end

      logger.debug "Bundle analysis response:"
      logger.debug_sub response

      begin
        response_json = JSON.parse(response.to_s)
        response_json["endpoints"].as_a.each do |ep|
          url = ep["url"].as_s
          method = ep["method"].as_s

          # Extract file path from the endpoint data if available
          # or use a default path
          path_info = if ep.as_h.has_key?("file") && !ep["file"].as_s.empty?
                        PathInfo.new(ep["file"].as_s)
                      else
                        PathInfo.new("#{base_path}/ai_detected")
                      end

          params = ep["params"].as_a.map do |param|
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

          details = Details.new(path_info)
          @result << Endpoint.new(url, method, params, details)
        end
      rescue e : Exception
        logger.warning "Error parsing bundle response: #{e.message}"
      end
    end

    private def select_target_paths(client : LLM::General) : Array(String)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")

      if all_paths.size > 10
        logger.debug_sub "AI::Analyzing filtered files"
        user_payload = all_paths.map { |p| "- #{File.expand_path(p)}" }.join("\n")
        messages = [{"role" => "system", "content" => LLM::SYSTEM_FILTER}, {"role" => "user", "content" => user_payload}]
        key = LLM::Cache.key(@llm_url, @model, "FILTER", LLM::FILTER_FORMAT, user_payload)
        filter_response = if cached = LLM::Cache.fetch(key)
                            cached
                          else
                            r = client.request_messages(messages, LLM::FILTER_FORMAT)
                            LLM::Cache.store(key, r.to_s)
                            r
                          end
        logger.debug_sub filter_response

        begin
          filtered = JSON.parse(filter_response.to_s)
          return filtered["files"].as_a.map(&.as_s)
        rescue e : Exception
          logger.debug "Error parsing filter response: #{e.message}"
          # fallback: analyze all files
          return Dir.glob("#{base_path}/**/*").reject { |p| File.directory?(p) || ignore_extensions.includes?(File.extname(p)) }
        end
      else
        logger.debug_sub "AI::Analyzing all files"
      end

      Dir.glob("#{base_path}/**/*").reject { |p| File.directory?(p) || ignore_extensions.includes?(File.extname(p)) }
    end

    private def analyze_file(path : String, client : LLM::General)
      return if File.directory?(path)
      relative_path = get_relative_path(base_path, path)

      if File.exists?(path) && !ignore_extensions.includes?(File.extname(path))
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          process_content(content, relative_path, path, client)
        end
      end
    rescue ex : Exception
      logger.debug "Error processing file: #{path}"
      logger.debug "Error: #{ex.message}"
    end

    private def process_content(content : String, relative_path : String, path : String, client : LLM::General)
      messages = [{"role" => "system", "content" => LLM::SYSTEM_ANALYZE}, {"role" => "user", "content" => content}]
      key = LLM::Cache.key(@llm_url, @model, "ANALYZE", LLM::ANALYZE_FORMAT, content)
      response = if cached = LLM::Cache.fetch(key)
                   cached
                 else
                   r = client.request_messages(messages, LLM::ANALYZE_FORMAT)
                   LLM::Cache.store(key, r.to_s)
                   r
                 end
      logger.debug "client response (#{relative_path}):"
      logger.debug_sub response

      begin
        response_json = JSON.parse(response.to_s)
        response_json["endpoints"].as_a.each do |ep|
          url = ep["url"].as_s
          method = ep["method"].as_s
          params = ep["params"].as_a.map do |param|
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
          details = Details.new(PathInfo.new(path))
          @result << Endpoint.new(url, method, params, details)
        end
      rescue e : Exception
        logger.debug "Error parsing response for file: #{path}"
        logger.debug "Error: #{e.message}"
      end
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
