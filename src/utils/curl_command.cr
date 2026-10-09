require "./control_chars"

# Shared curl command construction used by the curl output builder and the
# HTML report's copy-as-curl feature.
module CurlCommand
  # Line breaks become `\r`/`\n` text so a command stays on one line, and any
  # other control character `\xNN` (`ControlChars`), so a route carrying
  # `\e]8;;…` cannot drive the terminal the command is printed to.
  def self.shell_quote(str : String) : String
    "'#{ControlChars.escape(str.gsub("\r", "\\r").gsub("\n", "\\n")).gsub("'", "'\\''")}'"
  end

  # An endpoint's multipart `(name, value)` text and file fields. No file
  # fields means the request is not an upload.
  def self.form_fields(params) : {Array(Tuple(String, String)), Array(Tuple(String, String))}
    text_fields = [] of Tuple(String, String)
    file_fields = [] of Tuple(String, String)
    params.each do |param|
      case param.request_type
      when "file"
        file_fields << {param.name, param.value}
      when "form"
        text_fields << {param.name, param.value}
      end
    end
    {text_fields, file_fields}
  end

  # The curl command for one verb of a baked endpoint: multipart when it has
  # a file field, `--data-raw` otherwise.
  def self.for_endpoint(method : String, baked, params) : String
    text_fields, file_fields = form_fields(params)
    if file_fields.empty?
      build(method, baked[:url], baked[:body], baked[:body_type], baked[:header], baked[:cookie])
    else
      build_multipart(method, baked[:url], text_fields, file_fields, baked[:header], baked[:cookie])
    end
  end

  def self.build(method : String, url : String, body : String, body_type : String,
                 headers : Array(String), cookies : Array(String)) : String
    parts = ["curl", "-i", "-g", "-X", shell_quote(method), shell_quote(url)]

    unless body.empty?
      content_type = body_type == "json" ? "application/json" : "application/x-www-form-urlencoded"
      parts << "--data-raw"
      parts << shell_quote(body)
      parts << "-H"
      parts << shell_quote("Content-Type: #{content_type}")
    end

    append_headers_and_cookies(parts, headers, cookies)
    parts.join(" ")
  end

  # Upload endpoints (`param_type: file`) must use `-F` so curl sends
  # multipart/form-data. `--data-raw` cannot carry a file part, and the
  # previous builders simply dropped every file field — `POST /modern.php`
  # printed only `name=` while `-f postman` / OAS kept `avatar`.
  #
  # `file_fields` are `(name, path_hint)`; an empty hint uses the field name
  # as the `@filename` placeholder (same idea as Postman's empty `src`).
  #
  # Text fields go out as `--form-string`, which curl sends verbatim. Under
  # `-F` a value opening with `<` or `@` is read from a local file, and a
  # `;type=` / `;filename=` suffix is parsed as a part attribute — so a
  # `--pvalue` payload such as `<script>…` failed with curl error 26, and
  # `@/etc/passwd` would have uploaded that file. Only the file parts keep
  # `-F`, because there the `@` is the point.
  def self.build_multipart(method : String, url : String,
                           text_fields : Array(Tuple(String, String)),
                           file_fields : Array(Tuple(String, String)),
                           headers : Array(String), cookies : Array(String)) : String
    parts = ["curl", "-i", "-g", "-X", shell_quote(method), shell_quote(url)]

    text_fields.each do |name, value|
      parts << "--form-string"
      parts << shell_quote("#{name}=#{value}")
    end

    file_fields.each do |name, path_hint|
      filename = path_hint.empty? ? name : path_hint
      parts << "-F"
      parts << shell_quote("#{name}=@#{filename}")
    end

    # curl sets the multipart Content-Type (with boundary) itself when `-F`
    # or `--form-string` is used; do not force urlencoded/json here.
    append_headers_and_cookies(parts, headers, cookies)
    parts.join(" ")
  end

  private def self.append_headers_and_cookies(parts : Array(String), headers : Array(String), cookies : Array(String))
    headers.each do |header|
      parts << "-H"
      parts << shell_quote(header)
    end

    cookies.each do |cookie|
      parts << "--cookie"
      parts << shell_quote(cookie)
    end
  end
end
