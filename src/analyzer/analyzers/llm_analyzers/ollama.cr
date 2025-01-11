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

      locator = CodeLocator.instance
      all_paths = locator.all("file_map").join("\n")

      # Filter files that are likely to contain endpoints
      filter_prompt = <<-PROMPT
      !! Respond only in JSON format. Do not include explanations, comments, or any additional text. !!
      ---
      Analyze the following list of file paths and identify which files are likely to represent endpoints, including API endpoints, web pages, or static resources.
      Return the result as a JSON array of file paths that should be analyzed further.

      File paths:
      #{all_paths}
      PROMPT

      filter_response = ollama.request(filter_prompt)
      filtered_paths = JSON.parse(filter_response.to_s)
      logger.debug_sub filter_response

      # Source Analysis
      begin
        filtered_paths.as_a.each do |jpath|
          path = jpath.as_s
          next if File.directory?(path)

          relative_path = get_relative_path(base_path, path)

          if File.exists?(path) && !(ignore_extensions().includes? File.extname(path))
            File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
              content = file.gets_to_end

              begin
                prompt = <<-PROMPT
                !! Respond only in JSON format. Do not include explanations, comments, or any additional text. !!
                ---
                Analyze the given source code and extract the endpoint and parameter details. Strictly follow this JSON structure:

                [
                  {
                    "url": "string / e.g., /api/v1/users",
                    "method": "string / e.g., GET, POST, PUT, DELETE",
                    "params": [
                      {
                        "name": "string / e.g., id",
                        "param_type": "string / one of: query, json, form, header, cookie, path",
                        "value": "string / optional, default empty"
                      }
                    ]
                  }
                ]

                - Ensure `param_type` uses only these values: `query`, `json`, `form`, `header`, `cookie`, `path`.
                - If no endpoints are found in the code, respond with an empty array `[]`.
                - Do not deviate from the specified JSON structure.

                Input Code:

                #{content}
                PROMPT

                response = ollama.request(prompt)
                logger.debug "Ollama response (#{relative_path}):"
                logger.debug_sub response

                response_json = JSON.parse(response.to_s)
                response_json.as_a.each do |endpoint|
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
              rescue ex : Exception
                puts "Error processing file: #{path}"
                puts "Error: #{ex.message}"
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      Fiber.yield

      @result
    end

    def ignore_extensions
      [".js", ".css", ".html", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico", ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar", ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".log", ".sql", ".bak", ".swp"]
    end
  end
end
