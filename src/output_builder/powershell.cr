require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderPowershell < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      cmd = "Invoke-WebRequest -Method #{endpoint.method} -Uri \"#{escape_powershell(baked[:url])}\""

      # Build headers hash including cookies
      header_parts = [] of String

      # Add cookies as Cookie header
      if !baked[:cookie].empty?
        cookie_header = baked[:cookie].map { |c| escape_powershell(c) }.join("; ")
        header_parts << "\"Cookie\"=\"#{cookie_header}\""
      end

      # Add other headers
      baked[:header].each do |h|
        parts = h.split(": ", 2)
        if parts.size == 2
          header_parts << "\"#{escape_powershell(parts[0])}\"=\"#{escape_powershell(parts[1])}\""
        else
          header_parts << "\"#{escape_powershell(h)}\"=\"\""
        end
      end

      # Add headers if present
      if !header_parts.empty?
        cmd += " -Headers @{#{header_parts.join("; ")}}"
      end

      # Add body
      if baked[:body] != ""
        if baked[:body_type] == "json"
          # Escape for PowerShell string
          escaped_body = escape_powershell(baked[:body])
          cmd += " -Body \"#{escaped_body}\" -ContentType \"application/json\""
        else
          # Form data
          escaped_body = escape_powershell(baked[:body])
          cmd += " -Body \"#{escaped_body}\" -ContentType \"application/x-www-form-urlencoded\""
        end
      end

      ob_puts cmd
    end
  end

  # Escape special PowerShell characters in strings
  private def escape_powershell(str : String) : String
    str
      .gsub("`", "``")   # Escape backticks
      .gsub("$", "`$")   # Escape dollar signs
      .gsub("\"", "`\"") # Escape double quotes
  end
end
