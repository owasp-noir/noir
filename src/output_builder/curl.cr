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

        baked[:header].each do |header|
          cmd += " -H \"#{header}\""
        end
      end

      ob_puts cmd
    end
  end
end
