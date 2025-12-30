require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCommon < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      r_method_color = case endpoint.method
                       when "GET"    then :green
                       when "POST"   then :blue
                       when "PUT"    then Colorize::Color256.new(208)
                       when "PATCH"  then Colorize::Color256.new(208)
                       when "DELETE" then :red
                       else               :default
                       end

      r_method = endpoint.method.colorize(r_method_color).toggle(@is_color)
      r_url = baked[:url].colorize(:light_yellow).toggle(@is_color)
      r_ws = ""
      r_buffer = "\n#{r_method} #{r_url}"

      if any_to_bool(@options["status_codes"]) || @options["exclude_codes"] != ""
        status_color = :light_green
        status_code = endpoint.details.status_code
        if status_code
          if status_code >= 500
            status_color = :light_magenta
          elsif status_code >= 400
            status_color = :light_red
          elsif status_code >= 300
            status_color = :cyan
          end
        else
          status_code = "error"
          status_color = :light_red
        end

        r_buffer += " [#{status_code}]".to_s.colorize(status_color).toggle(@is_color).to_s
      end

      if endpoint.protocol == "ws"
        r_ws = "[websocket]".colorize(:light_red).toggle(@is_color)
        r_buffer += " #{r_ws}"
      end

      if baked[:header].size > 0
        r_buffer += "\n  ○ headers: "
        baked[:header].each_with_index do |header, index|
          prefix = index == baked[:header].size - 1 ? "└── " : "├── "
          r_header = "#{prefix}#{header}".colorize(:light_green).toggle(@is_color)
          r_buffer += "\n    #{r_header}"
        end
      end

      if baked[:cookie].size > 0
        r_buffer += "\n  ○ cookies: "
        baked[:cookie].each_with_index do |cookie, index|
          prefix = index == baked[:cookie].size - 1 ? "└── " : "├── "
          r_cookie = "#{prefix}#{cookie}".colorize(:light_green).toggle(@is_color)
          r_buffer += "\n    #{r_cookie}"
        end
      end

      if baked[:path_param].size > 0
        r_path_param = baked[:path_param].join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer += "\n  ○ path: #{r_path_param}"
      end

      if baked[:body] != ""
        r_body = baked[:body].colorize(:cyan).toggle(@is_color)
        r_buffer += "\n  ○ body: #{r_body}"
      end

      tags = baked[:tags]
      endpoint.tags.each do |tag|
        tags << tag.name.to_s
      end

      if tags.size > 0
        r_tags = tags.join(" ").colorize(:light_magenta).toggle(@is_color)
        r_buffer += "\n  ○ tags: #{r_tags}"
      end

      # Always show technology if available
      if endpoint.details.technology
        r_tech = endpoint.details.technology.to_s.colorize(:light_blue).toggle(@is_color)
        r_buffer += "\n  ○ tech: #{r_tech}"
      end

      if any_to_bool(@options["include_path"])
        details = endpoint.details
        if details.code_paths && !details.code_paths.empty?
          details.code_paths.each do |code_path|
            if code_path.line.nil?
              r_buffer += "\n  ○ file: #{code_path.path}"
            else
              r_buffer += "\n  ○ file: #{code_path.path} (line #{code_path.line})"
            end
          end
        end
      end

      ob_puts r_buffer
    end
  end
end
