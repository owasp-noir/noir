require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderPowershell < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      cmd = "Invoke-WebRequest -Method #{endpoint.method} -Uri \"#{baked[:url]}\""

      # Add headers
      if !baked[:header].empty?
        headers = baked[:header].map { |h|
          parts = h.split(": ", 2)
          if parts.size == 2
            "\"#{parts[0]}\"=\"#{parts[1]}\""
          else
            "\"#{h}\"=\"\""
          end
        }.join("; ")
        cmd += " -Headers @{#{headers}}"
      end

      # Add cookies
      if !baked[:cookie].empty?
        # Create a WebRequestSession for cookies
        cookie_header = baked[:cookie].join("; ")
        if baked[:header].empty?
          cmd += " -Headers @{\"Cookie\"=\"#{cookie_header}\"}"
        else
          # Add cookie to existing headers
          cmd = cmd.sub(" -Headers @{", " -Headers @{\"Cookie\"=\"#{cookie_header}\"; ")
        end
      end

      # Add body
      if baked[:body] != ""
        if baked[:body_type] == "json"
          # Escape double quotes in JSON body
          escaped_body = baked[:body].gsub("\"", "`\"")
          cmd += " -Body \"#{escaped_body}\" -ContentType \"application/json\""
        else
          # Form data
          cmd += " -Body \"#{baked[:body]}\" -ContentType \"application/x-www-form-urlencoded\""
        end
      end

      ob_puts cmd
    end
  end
end
