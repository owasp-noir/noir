require "../../../models/analyzer"

module Analyzer::Specification
  class Postman < Analyzer
    def analyze
      locator = CodeLocator.instance
      postman_files = locator.all("postman-json")

      if postman_files.is_a?(Array(String))
        postman_files.each do |postman_file|
          if File.exists?(postman_file)
            details = Details.new(PathInfo.new(postman_file))
            content = File.read(postman_file, encoding: "utf-8", invalid: :skip)
            json_obj = JSON.parse(content)

            begin
              # Process items (requests) in the collection
              if json_obj["item"]?
                process_items(json_obj["item"], details)
              end
            rescue e
              @logger.debug "Exception processing #{postman_file}"
              @logger.debug_sub e
            end
          end
        end
      end

      @result
    end

    private def process_items(items, details, folder_path = "")
      items.as_a.each do |item|
        begin
          # Check if it's a folder (has nested items) or a request
          if item["item"]?
            # It's a folder, recurse into it
            folder_name = item["name"]?.try(&.to_s) || ""
            new_path = folder_path.empty? ? folder_name : "#{folder_path}/#{folder_name}"
            process_items(item["item"], details, new_path)
          elsif item["request"]?
            # It's a request, process it
            process_request(item, details)
          end
        rescue e
          @logger.debug "Exception processing item"
          @logger.debug_sub e
        end
      end
    end

    private def process_request(item, details)
      request = item["request"]

      # Get HTTP method
      method = "GET"
      if request.is_a?(JSON::Any) && request["method"]?
        method = request["method"].to_s.upcase
      elsif request.is_a?(String)
        # Simple request format (just a URL string)
        return
      end

      # Get URL
      url_path = ""
      params = [] of Param

      if request["url"]?
        url = request["url"]

        # Check if URL is a simple string (v2.0.0 format) or object (v2.1.0 format)
        begin
          url_string = url.as_s
          # URL is a string
          url_path = extract_path_from_url(url_string)
        rescue
          # URL is an object
          # Extract path
          if url["path"]?
            if url["path"].as_a?
              url_path = "/" + url["path"].as_a.map(&.to_s).join("/")
            elsif url["path"].as_s?
              url_path = url["path"].to_s
            end
          elsif url["raw"]?
            url_path = extract_path_from_url(url["raw"].to_s)
          end

          # Extract query parameters
          if url["query"]?
            url["query"].as_a.each do |query_param|
              if query_param["key"]?
                param_name = query_param["key"].to_s
                param_value = query_param["value"]?.try(&.to_s) || ""
                params << Param.new(param_name, param_value, "query")
              end
            rescue
            end
          end

          # Extract path variables
          if url["variable"]?
            url["variable"].as_a.each do |path_var|
              if path_var["key"]?
                param_name = path_var["key"].to_s
                param_value = path_var["value"]?.try(&.to_s) || ""
                params << Param.new(param_name, param_value, "path")
              end
            rescue
            end
          end
        end
      end

      # Extract headers
      if request["header"]?
        request["header"].as_a.each do |header|
          if header["key"]?
            param_name = header["key"].to_s
            param_value = header["value"]?.try(&.to_s) || ""
            # Skip common headers that are not user-controllable
            unless param_name.downcase == "content-type"
              params << Param.new(param_name, param_value, "header")
            end
          end
        rescue
        end
      end

      # Extract body parameters
      if request["body"]?
        body = request["body"]
        mode = body["mode"]?.try(&.to_s) || ""

        case mode
        when "raw"
          # Try to parse as JSON
          if body["raw"]?
            raw_content = body["raw"].to_s
            begin
              json_body = JSON.parse(raw_content)
              if json_body.as_h?
                json_body.as_h.each do |key, value|
                  params << Param.new(key, value.to_s, "json")
                end
              end
            rescue
              # Not JSON, treat as raw body
            end
          end
        when "urlencoded"
          if body["urlencoded"]?
            body["urlencoded"].as_a.each do |form_param|
              if form_param["key"]?
                param_name = form_param["key"].to_s
                param_value = form_param["value"]?.try(&.to_s) || ""
                params << Param.new(param_name, param_value, "form")
              end
            rescue
            end
          end
        when "formdata"
          if body["formdata"]?
            body["formdata"].as_a.each do |form_param|
              if form_param["key"]?
                param_name = form_param["key"].to_s
                param_value = form_param["value"]?.try(&.to_s) || ""
                params << Param.new(param_name, param_value, "form")
              end
            rescue
            end
          end
        end
      end

      # Create endpoint
      if !url_path.empty?
        @result << Endpoint.new(url_path, method, params, details)
      end
    rescue e
      @logger.debug "Exception processing request"
      @logger.debug_sub e
    end

    private def extract_path_from_url(url_string : String) : String
      # Extract path from a full URL string
      begin
        uri = URI.parse(url_string)
        return uri.path || "/"
      rescue
        # If parsing fails, try to extract path manually
        # Remove protocol if present
        url = url_string.sub(/^https?:\/\//, "")
        # Remove host and port
        if url.includes?("/")
          return "/" + url.split("/", 2)[1].split("?")[0]
        end
      end
      "/"
    end
  end
end
