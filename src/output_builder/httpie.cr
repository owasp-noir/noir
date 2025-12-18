require "../models/output_builder"
require "../models/endpoint"
require "json"
require "uri"

class OutputBuilderHttpie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      # Quote the URL properly
      cmd = "http #{endpoint.method} '#{escape_shell(baked[:url])}'"
      
      # For HTTPie, we need to handle JSON differently
      if baked[:body] != ""
        if baked[:body_type] == "json"
          # Parse JSON and convert to HTTPie's key:=value syntax
          begin
            json_data = JSON.parse(baked[:body])
            if json_data.as_h?
              json_data.as_h.each do |key, value|
                # Use := for JSON fields (only use to_json for non-string types)
                if value.raw.is_a?(String)
                  escaped_value = escape_shell(value.as_s)
                  cmd += " #{key}:='#{escaped_value}'"
                else
                  escaped_value = escape_shell(value.to_json)
                  cmd += " #{key}:='#{escaped_value}'"
                end
              end
            else
              # For arrays and primitives, HTTPie can handle them directly
              cmd += " '#{escape_shell(baked[:body])}'"
            end
          rescue
            # If parsing fails, use the body as-is
            cmd += " '#{escape_shell(baked[:body])}'"
          end
        else
          # For form data, use key=value syntax
          form_parts = baked[:body].split('&')
          form_parts.each do |part|
            if part.includes?('=')
              key_value = part.split('=', 2)
              # URL decode the value before escaping for HTTPie
              begin
                decoded_value = URI.decode_www_form(key_value[1])
                cmd += " #{key_value[0]}='#{escape_shell(decoded_value)}'"
              rescue
                # If decoding fails, use the value as-is
                cmd += " #{key_value[0]}='#{escape_shell(key_value[1])}'"
              end
            end
          end
        end
      end

      # Headers: use Header:Value format (no quotes around the header directive)
      baked[:header].each do |header|
        cmd += " '#{escape_shell(header)}'"
      end

      # Cookies: add as Cookie header
      if !baked[:cookie].empty?
        cookie_value = baked[:cookie].join("; ")
        cmd += " 'Cookie:#{escape_shell(cookie_value)}'"
      end

      ob_puts cmd
    end
  end

  # Escape special characters for shell (using single quotes)
  private def escape_shell(str : String) : String
    str.gsub("'", "'\\''")
  end
end
