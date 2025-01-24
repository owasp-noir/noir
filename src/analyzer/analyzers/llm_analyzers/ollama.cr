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
      all_paths = locator.all("file_map")
      target_paths = [] of String

      if all_paths.size > 10
        logger.debug_sub "Ollama::Analyzing filtered files"

        # Filter files that are likely to contain endpoints
        filter_prompt = <<-PROMPT
        Analyze the provided list of file paths and identify individual files that are likely to represent endpoints, such as API endpoints, web pages, or static resources. 
        Ignore directories and focus exclusively on files.

        Return the result strictly in the following JSON structure:
        {
          "files": [
            "string / e.g., /path/to/file1",
            "string / e.g., /path/to/file2",
            "string / e.g., /path/to/file3"
          ]
        }

        If no relevant files are found, return:
        {
          "files": []
        }

        Guidelines:
        - Do not include directories in the output.
        - Focus on files related to endpoints (API, web pages, or static resources).
        - Provide only the JSON response with no explanations or additional text.

        File paths:
        #{all_paths.join("\n")}
        PROMPT

        filter_response = ollama.request(filter_prompt)
        filtered_paths = JSON.parse(filter_response.to_s)
        logger.debug_sub filter_response

        filtered_paths["files"].as_a.each do |fpath|
          target_paths << fpath.as_s
        end
      else
        logger.debug_sub "Ollama::Analyzing all files"
        target_paths = Dir.glob("#{base_path}/**/*")
      end

      # Source Analysis
      begin
        target_paths.each do |path|
          next if File.directory?(path)

          relative_path = get_relative_path(base_path, path)

          if File.exists?(path) && !(ignore_extensions().includes? File.extname(path))
            File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
              content = file.gets_to_end

              begin
                prompt = <<-PROMPT
                Analyze the provided source code to extract details about the endpoints and their parameters.

                Return the result strictly in the following JSON structure:
                {
                  "endpoints": [
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
                }

                If no endpoints are found, return:
                {"endpoints": []}

                Guidelines:
                - `param_type` must strictly use one of these values: `query`, `json`, `form`, `header`, `cookie`, `path`.
                - Do not include explanations, comments, or additional text.
                - Provide only the JSON response as output.

                Input Code:
                #{content}
                PROMPT

                response = ollama.request(prompt)
                logger.debug "Ollama response (#{relative_path}):"
                logger.debug_sub response

                response_json = JSON.parse(response.to_s)
                next unless response_json["endpoints"].as_a.size > 0
                response_json["endpoints"].as_a.each do |endpoint|
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
      [".css", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico", ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar", ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".log", ".sql", ".bak", ".swp"]
    end
  end
end
