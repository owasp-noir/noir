require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCommon < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      r_method = endpoint.method.colorize(:light_blue).toggle(@is_color)
      r_url = baked[:url].colorize(:light_yellow).toggle(@is_color)
      r_headers = baked[:header].join(" ").colorize(:light_green).toggle(@is_color)

      r_ws = ""
      if endpoint.protocol == "ws"
        r_ws = "[WEBSOCKET]".colorize(:light_red).toggle(@is_color)
      end

      if baked[:body] != ""
        r_body = baked[:body].colorize(:cyan).toggle(@is_color)
        puts "#{r_method} #{r_url} #{r_body} #{r_headers} #{r_ws}"
      else
        puts "#{r_method} #{r_url} #{r_headers} #{r_ws}"
      end
    end
  end
end
