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

      if any_to_bool(@options["include_path"]) == true
        details = endpoint.details
        if details.code_paths && details.code_paths.size > 0
          details.code_paths.each do |code_path|
            if code_path.line.nil?
              r_buffer += "\n  ○ file: #{code_path.path}"
            else
              r_buffer += "\n  ○ file: #{code_path.path} (line #{code_path.line})"
            end
          end
        end
      end

      if any_to_bool(@options["show_status"]) == true || @options["exclude_status"] != ""
        r_status = endpoint.details.status_code.to_s.colorize(:light_yellow).toggle(@is_color)
        r_buffer += "\n  ○ status: #{r_status}"
      end

      ob_puts r_buffer
    end
  end
end
