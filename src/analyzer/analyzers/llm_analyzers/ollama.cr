require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/ollama"

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
      # Init LLM Instance
      ollama = LLM::Ollama.new(@llm_url, @model)

      # Source Analysis
      begin
        Dir.glob("#{base_path}/**/*") do |path|
          next if File.directory?(path)

          relative_path = get_relative_path(base_path, path)

          if File.exists?(path) && !(ingnore_extensions.includes? File.extname(path))
            File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
              params_query = [] of Param
              params_body = [] of Param
              methods = [] of String

              file.each_line do |_|
                # TODO
                # puts ollama.request("Hi! This is prompt text.")
                # details = Details.new(PathInfo.new(path))
                # result << Endpoint.new("/#{relative_path}", method, params_body, details)


              rescue
                next
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      Fiber.yield

      result
    end

    def ingnore_extensions
      [".js", ".css", ".html", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico", ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar", ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".log", ".sql", ".bak", ".swp"]
    end
  end
end
