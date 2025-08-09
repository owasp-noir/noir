require "../../../models/analyzer"

module Analyzer::Rust
  class Loco < Analyzer
    def analyze
      # Source Analysis for Loco framework routes
      # Loco follows Rails conventions with controllers and actions
      
      # Simple pattern to match function definitions
      pattern = /pub\s+async\s+fn\s+(\w+)/
      
      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  if File.exists?(path) && File.extname(path) == ".rs"
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line.with_index do |line, index|
                        if line.to_s.includes? "pub async fn"
                          match = line.match(pattern)
                          if match
                            begin
                              method_name = match[1]
                              # Convert Rails-style action names to route paths
                              endpoint_path = action_to_path(method_name, path)
                              details = Details.new(PathInfo.new(path, index + 1))
                              # Infer HTTP method from action name and context
                              http_method = infer_http_method(method_name, line)
                              result << Endpoint.new(endpoint_path, http_method, details)
                            rescue e
                              # Log the exception for debugging
                              logger.debug "Error parsing Loco endpoint: #{e.message}"
                            end
                          end
                        end
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                rescue e
                  logger.debug "Error in Loco analyzer: #{e.message}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in Loco analyzer setup: #{e.message}"
      end

      result
    end

    private def action_to_path(action_name : String, file_path : String) : String
      # Extract controller name from file path if possible
      controller = ""
      if file_path.includes?("/controllers/") || file_path.includes?("/controller/")
        path_parts = file_path.split("/")
        controller_file = path_parts.last.gsub(/\.rs$/, "")
        controller = controller_file.gsub(/_controller$/, "")
      end

      # Convert Rails-style action names to RESTful paths
      case action_name
      when "index"
        controller.empty? ? "/" : "/#{controller}"
      when "show"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "new"
        controller.empty? ? "/new" : "/#{controller}/new"
      when "create"
        controller.empty? ? "/" : "/#{controller}"
      when "edit"
        controller.empty? ? "/:id/edit" : "/#{controller}/:id/edit"
      when "update"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "destroy", "delete"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      else
        # For custom actions, create a path based on action name
        base_path = controller.empty? ? "" : "/#{controller}"
        "#{base_path}/#{action_name.gsub(/([A-Z])/, "_\\1").downcase.lstrip("_")}"
      end
    end

    private def infer_http_method(action_name : String, line : String) : String
      # Infer HTTP method from Rails conventions and line context
      case action_name
      when "index", "show", "new", "edit"
        "GET"
      when "create"
        "POST"
      when "update"
        if line.includes?("PUT") || line.includes?("put")
          "PUT"
        else
          "PATCH"
        end
      when "destroy", "delete"
        "DELETE"
      else
        # Check line for HTTP method hints
        if line.includes?("post") || line.includes?("POST")
          "POST"
        elsif line.includes?("put") || line.includes?("PUT")
          "PUT"
        elsif line.includes?("delete") || line.includes?("DELETE")
          "DELETE"
        elsif line.includes?("patch") || line.includes?("PATCH")
          "PATCH"
        else
          "GET"
        end
      end
    end
  end
end