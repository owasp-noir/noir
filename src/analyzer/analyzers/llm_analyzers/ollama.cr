require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/ollama"
require "../../../llm/prompt"

module Analyzer::AI
  class Ollama < Analyzer
    @llm_url : String
    @model : String

    def initialize(options : Hash(String, YAML::Any))
      super(options)
      @llm_url = options["ollama"].as_s
      @model = options["ollama_model"].as_s
    end

    def analyze
      ollama = LLM::Ollama.new(@llm_url, @model)
      target_paths = select_target_paths(ollama)
      target_paths.each { |path| analyze_file(path, ollama) }
      Fiber.yield
      @result
    end

    private def select_target_paths(ollama : LLM::Ollama) : Array(String)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")

      if all_paths.size > 10
        logger.debug_sub "Ollama::Analyzing filtered files"
        prompt = "#{LLM::FILTER_PROMPT}\n" +
                 all_paths.map { |p| "- #{File.expand_path(p)}" }.join("\n")
        filter_response = ollama.request(prompt, LLM::FILTER_FORMAT)
        logger.debug_sub filter_response

        begin
          filtered = JSON.parse(filter_response.to_s)
          return filtered["files"].as_a.map(&.as_s)
        rescue e : Exception
          logger.debug "Error parsing filter response: #{e.message}"
          # fallback: 분석대상 전체 파일
        end
      else
        logger.debug_sub "Ollama::Analyzing all files"
      end
      Dir.glob("#{base_path}/**/*")
    end

    private def analyze_file(path : String, ollama : LLM::Ollama)
      return if File.directory?(path)
      relative_path = get_relative_path(base_path, path)

      if File.exists?(path) && !ignore_extensions.includes?(File.extname(path))
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          process_content(content, relative_path, path, ollama)
        end
      end
    rescue ex : Exception
      logger.debug "Error processing file: #{path}"
      logger.debug "Error: #{ex.message}"
    end

    private def process_content(content : String, relative_path : String, path : String, ollama : LLM::Ollama)
      prompt = "#{LLM::ANALYZE_PROMPT}\n#{content}"
      response = ollama.request(prompt, LLM::ANALYZE_FORMAT)
      logger.debug "Ollama response (#{relative_path}):"
      logger.debug_sub response

      begin
        response_json = JSON.parse(response.to_s)
        endpoints = response_json["endpoints"].as_a
        return if endpoints.empty?

        endpoints.each do |endpoint|
          url = endpoint["url"].as_s
          method = endpoint["method"].as_s
          params = endpoint["params"].as_a.map do |param|
            Param.new(
              param["name"].as_s,
              param["value"].as_s,
              param["param_type"].as_s
            )
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
