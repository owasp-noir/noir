require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderHttpie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      cmd = "http #{endpoint.method} #{baked[:url]}"
      if baked[:body] != ""
        cmd += " \"#{baked[:body]}\""
        if baked[:body_type] == "json"
          cmd += " \"Content-Type:application/json\""
        end
      end

      baked[:header].each do |header|
        cmd += " \"#{header}\""
      end

      baked[:cookie].each do |cookie|
        cmd += " \"Cookie: #{cookie}\""
      end

      ob_puts cmd
    end
  end
end
