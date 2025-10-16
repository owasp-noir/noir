require "../../../models/analyzer"

module Analyzer::Ruby
  class Hanami < Analyzer
    def analyze
      # Config Analysis
      path = "#{@base_path}/config/routes.rb"
      if File.exists?(path)
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          last_endpoint = Endpoint.new("", "")
          file.each_line.with_index do |line, index|
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = line_to_endpoint(line, details)
            if endpoint.method != ""
              # Extract action path from route
              action_path = extract_action_path(line)
              if action_path != ""
                # Scan action file for parameters
                scan_action_file(endpoint, action_path)
              end
              
              @result << endpoint
              last_endpoint = endpoint
              _ = last_endpoint
            end
          end
        end
      end

      @result
    end

    def extract_action_path(content : String) : String
      # Extract action from to: parameter, e.g., to: "books.index" -> app/actions/books/index.rb
      content.scan(/to:\s*['"](.+?)['"]/) do |match|
        if match.size > 1
          action = match[1]
          # Convert "books.index" to "app/actions/books/index.rb"
          return "#{@base_path}/app/actions/#{action.gsub(".", "/")}.rb"
        end
      end
      ""
    end

    def scan_action_file(endpoint : Endpoint, action_path : String)
      return unless File.exists?(action_path)

      File.open(action_path, "r", encoding: "utf-8", invalid: :skip) do |file|
        in_params_block = false
        
        file.each_line do |line|
          # Detect params block
          if line.strip == "params do"
            in_params_block = true
            next
          elsif line.strip == "end" && in_params_block
            in_params_block = false
            next
          end

          # Extract params from params block
          if in_params_block
            # Match required(:name) or optional(:name)
            line.scan(/(?:required|optional)\(:([\w]+)\)/) do |match|
              if match.size > 1
                param_name = match[1]
                # Determine if it's JSON or form based on content type
                param_type = "json"
                endpoint.push_param(Param.new(param_name, "", param_type))
              end
            end
          end

          # Extract query parameters from request.params[:name]
          line.scan(/request\.params\[:([\w]+)\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end

          # Extract header parameters from request.headers['name'] or request.headers["name"]
          line.scan(/request\.headers\[['"](.+?)['"]\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "header"))
            end
          end

          # Extract cookie parameters from request.cookies['name'] or request.cookies["name"]
          line.scan(/request\.cookies\[['"](.+?)['"]\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "cookie"))
            end
          end
        end
      end
    end

    def line_to_endpoint(content : String, details : Details) : Endpoint
      content.scan(/get\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "GET", details)
        end
      end

      content.scan(/post\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "POST", details)
        end
      end

      content.scan(/put\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "PUT", details)
        end
      end

      content.scan(/delete\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "DELETE", details)
        end
      end

      content.scan(/patch\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "PATCH", details)
        end
      end

      content.scan(/head\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "HEAD", details)
        end
      end

      content.scan(/options\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "OPTIONS", details)
        end
      end

      Endpoint.new("", "")
    end
  end
end
