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
        Analyze the following list of file paths and identify which files are likely to represent endpoints, including API endpoints, web pages, or static resources.

        Guidelines:
        - Focus only on individual files.
        - Do not include directories.
        - Do not include explanations, comments or additional text.

        Input Files:
        #{all_paths.map { |path| "- #{File.expand_path(path)}" }.join("\n")}
        PROMPT

        format = <<-FORMAT
        {
          "type": "object",
          "properties": {
            "files": {
              "type": "array",
              "items": {
                "type": "string"
              }
            }
          },
          "required": ["files"]
        }
        FORMAT

        filter_response = ollama.request(filter_prompt, format)
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

                Guidelines:
                - The "method" field should strictly use one of these values: "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD".
                - The "param_type" must strictly use one of these values: "query", "json", "form", "header", "cookie" and "path".
                - Do not include explanations, comments or additional text.

                Input Code:
                #{content}
                PROMPT

                format = <<-FORMAT
                {
                  "type": "object",
                  "properties": {
                    "endpoints": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": {
                          "url": {
                            "type": "string"
                          },
                          "method": {
                            "type": "string"
                          },
                          "params": {
                            "type": "array",
                            "items": {
                              "type": "object",
                              "properties": {
                                "name": {
                                  "type": "string"
                                },
                                "param_type": {
                                  "type": "string"
                                },
                                "value": {
                                  "type": "string"
                                }
                              },
                              "required": ["name", "param_type", "value"]
                            }
                          }
                        },
                        "required": ["url", "method", "params"]
                      }
                    }
                  },
                  "required": ["endpoints"]
                }
                FORMAT

                response = ollama.request(prompt, format)
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
                logger.debug "Error processing file: #{path}"
                logger.debug "Error: #{ex.message}"
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
      [".css", ".xml", ".json", ".yml", ".yaml", ".md", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico", ".eot", ".ttf", ".woff", ".woff2", ".otf", ".mp3", ".mp4", ".avi", ".mov", ".webm", ".zip", ".tar", ".gz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".log", ".sql", ".bak", ".swp", ".jar"]
    end
  end
end
