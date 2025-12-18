require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      # Properly quote and escape the URL
      cmd = "curl -i -X #{endpoint.method} '#{escape_shell(baked[:url])}'"
      
      if baked[:body] != ""
        if baked[:body_type] == "json"
          # For JSON, use single quotes to avoid shell interpolation issues
          cmd += " -d '#{escape_shell(baked[:body])}'"
          cmd += " -H 'Content-Type: application/json'"
        else
          # For form data, escape properly
          cmd += " -d '#{escape_shell(baked[:body])}'"
          cmd += " -H 'Content-Type: application/x-www-form-urlencoded'"
        end
      end

      baked[:header].each do |header|
        cmd += " -H '#{escape_shell(header)}'"
      end

      baked[:cookie].each do |cookie|
        cmd += " --cookie '#{escape_shell(cookie)}'"
      end

      ob_puts cmd
    end
  end

  # Escape special characters for shell (using single quotes)
  private def escape_shell(str : String) : String
    str.gsub("'", "'\\''")
  end
end
