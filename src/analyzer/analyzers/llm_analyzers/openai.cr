require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/openai"
require "../../../llm/prompt"

module Analyzer::AI
  class OpenAI < Analyzer
    @llm_url : String
    @model : String
    @api_key : String?

    def initialize(options : Hash(String, YAML::Any))
      super(options)
      raw_server = options["ai_server"].as_s
      @llm_url = if raw_server.includes?("://")
                   raw_server
                 else
                   case raw_server.downcase
                   when "openai"
                     "https://api.openai.com"
                   when "ollama"
                     "http://localhost:11434"
                   when "x.ai"
                     "https://api.x.ai"
                   when "vllm"
                     "http://localhost:8000"
                   else
                     raw_server
                   end
                 end
      @model = options["ai_model"].as_s
      @api_key = options["ai_key"].as_s
    end

    def analyze
      openai = LLM::OpenAI.new(@llm_url, @model, @api_key)
      target_paths = select_target_paths(openai)
      target_paths.each { |path| analyze_file(path, openai) }
      Fiber.yield
      @result
    end

    private def select_target_paths(openai : LLM::OpenAI) : Array(String)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")

      if all_paths.size > 10
        logger.debug_sub "OpenAI::Analyzing filtered files"
        prompt = "#{LLM::FILTER_PROMPT}\n" +
                 all_paths.map { |p| "- #{File.expand_path(p)}" }.join("\n")
        filter_response = openai.request(prompt, LLM::FILTER_FORMAT)
        logger.debug_sub filter_response

        begin
          filtered = JSON.parse(filter_response.to_s)
          return filtered["files"].as_a.map(&.as_s)
        rescue e : Exception
          logger.debug "Error parsing filter response: #{e.message}"
          # fallback: analyze all files
        end
      else
        logger.debug_sub "OpenAI::Analyzing all files"
      end
      Dir.glob("#{base_path}/**/*")
    end

    private def analyze_file(path : String, openai : LLM::OpenAI)
      return if File.directory?(path)
      relative_path = get_relative_path(base_path, path)

      if File.exists?(path) && !ignore_extensions.includes?(File.extname(path))
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          process_content(content, relative_path, path, openai)
        end
      end
    rescue ex : Exception
      logger.debug "Error processing file: #{path}"
      logger.debug "Error: #{ex.message}"
    end

    private def process_content(content : String, relative_path : String, path : String, openai : LLM::OpenAI)
      prompt = "#{LLM::ANALYZE_PROMPT}\n#{content}"
      response = openai.request(prompt, LLM::ANALYZE_FORMAT)
      logger.debug "OpenAI response (#{relative_path}):"
      logger.debug_sub response

      begin
        response_json = JSON.parse(response.to_s)
        response_json.as_a.each do |ep|
          url = ep["path"].as_s
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
  end
end
