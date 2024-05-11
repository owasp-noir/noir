require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      cmd = "curl -i -X #{endpoint.method} #{baked[:url]}"
      if baked[:body] != ""
        cmd += " -d \"#{baked[:body]}\""
        if baked[:body_type] == "json"
          cmd += " -H \"Content-Type:application/json\""
        end
      end

      baked[:header].each do |header|
        cmd += " -H \"#{header}\""
      end

      baked[:cookie].each do |cookie|
        cmd += " --cookie \"#{cookie}\""
      end

      ob_puts cmd
    end
  end
end
