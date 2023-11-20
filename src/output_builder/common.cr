require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCommon < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      r_method = endpoint.method.colorize(:light_blue).toggle(@is_color)
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

      ob_puts r_buffer
    end
  end
end
