require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "../utils/curl_command"

@[Noir::OutputFormat(name: "powershell", description: "PowerShell Invoke-WebRequest commands", order: 110)]
class OutputBuilderPowershell < OutputBuilder
  # The verbs Invoke-WebRequest's `-Method` accepts — it validates against
  # the WebRequestMethod enum, so a verb outside this set (QUERY, CONNECT)
  # is rejected before any request is sent and must go through
  # `-CustomMethod` instead. The two flags are otherwise equivalent.
  ENUM_METHODS = Set{"GET", "HEAD", "POST", "PUT", "DELETE", "TRACE", "OPTIONS", "MERGE", "PATCH"}

  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      expand_synthetic_http_methods(endpoint.method).each do |method|
        method_flag = ENUM_METHODS.includes?(method) ? "-Method" : "-CustomMethod"
        cmd = "Invoke-WebRequest #{method_flag} \"#{escape_powershell(method)}\" -Uri \"#{escape_powershell(baked[:url])}\""

        headers = baked[:header].map do |h|
          parts = h.split(": ", 2)
          {parts[0], parts[1]? || ""}
        end

        # Cookies go out as one Cookie header, first, folded together with
        # any header param that is itself named Cookie.
        unless baked[:cookie].empty?
          cookies = headers.compact_map { |name, value| value if name.downcase == "cookie" && !value.empty? }
          headers.reject! { |name, _| name.downcase == "cookie" }
          headers.unshift({"Cookie", (cookies + baked[:cookie]).join("; ")})
        end

        unless headers.empty?
          cmd += " -Headers #{hash_literal(headers.map { |name, value| {name, "\"#{escape_powershell(value)}\""} })}"
        end

        # Upload endpoints (`param_type: file`) need `-Form` so PowerShell
        # sends multipart/form-data. `-Body` cannot carry a file part, and
        # bake_endpoint drops every file field — the same gap curl/httpie
        # had before they grew `-F` / `--form`. Sibling form fields ride
        # along; PowerShell sets the multipart Content-Type itself.
        form_fields, file_fields = CurlCommand.form_fields(endpoint.params)

        if !file_fields.empty?
          form_parts = form_fields.map { |name, value| {name, "\"#{escape_powershell(value)}\""} }
          file_fields.each do |name, path_hint|
            filename = path_hint.empty? ? name : path_hint
            form_parts << {name, "Get-Item -Path \"#{escape_powershell(filename)}\""}
          end
          cmd += " -Form #{hash_literal(form_parts)}"
        elsif !baked[:body].empty?
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
  end

  # `@{"k"=<expr>; ...}` from `{key, rendered value}` pairs. A PowerShell hash
  # literal's keys are case-insensitive and a repeat is a parse error
  # ("Duplicate keys 'x-a' are not allowed in hash literals"), so headers
  # `X-A` and `x-a` broke the whole command; the first spelling wins.
  private def hash_literal(entries : Array({String, String})) : String
    seen = Set(String).new
    parts = entries.compact_map do |key, value|
      "\"#{escape_powershell(key)}\"=#{value}" if seen.add?(key.downcase)
    end
    "@{#{parts.join("; ")}}"
  end

  # Escape special PowerShell characters in strings
  # Note: We wrap values in double quotes, so single quotes don't need escaping
  private def escape_powershell(str : String) : String
    str
      .gsub("`", "``")   # Escape backticks
      .gsub("$", "`$")   # Escape dollar signs
      .gsub("\"", "`\"") # Escape double quotes
      .gsub("\r", "`r")  # Escape carriage return
      .gsub("\n", "`n")  # Escape newline
  end
end
