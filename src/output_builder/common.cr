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
      r_headers = baked[:header].join(" ").colorize(:light_green).toggle(@is_color)
      r_cookies = baked[:cookie].join(";").colorize(:light_green).toggle(@is_color)
      r_ws = ""
      r_buffer = "#{r_method} #{r_url}"

      if endpoint.protocol == "ws"
        r_ws = "[websocket]".colorize(:light_red).toggle(@is_color)
        r_buffer += " #{r_ws}"
      end

      if baked[:header].size > 0
        r_buffer += "\n  ○ headers: #{r_headers}"
      end

      if baked[:cookie].size > 0
        r_buffer += "\n  ○ cookies: #{r_cookies}"
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

      if @options["include_path"] == "yes"
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

      ob_puts r_buffer
    end
  end
end
