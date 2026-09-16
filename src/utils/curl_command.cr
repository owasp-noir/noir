# Shared curl command construction used by the curl output builder and the
# HTML report's copy-as-curl feature.
module CurlCommand
  def self.shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''").gsub("\r", "\\r").gsub("\n", "\\n")}'"
  end

  def self.build(method : String, url : String, body : String, body_type : String,
                 headers : Array(String), cookies : Array(String)) : String
    parts = ["curl", "-i", "-X", shell_quote(method), shell_quote(url)]

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
  def self.build_multipart(method : String, url : String,
                           text_fields : Array(Tuple(String, String)),
                           file_fields : Array(Tuple(String, String)),
                           headers : Array(String), cookies : Array(String)) : String
    parts = ["curl", "-i", "-X", shell_quote(method), shell_quote(url)]

    text_fields.each do |name, value|
      parts << "-F"
      parts << shell_quote("#{name}=#{value}")
    end

    file_fields.each do |name, path_hint|
      filename = path_hint.empty? ? name : path_hint
      parts << "-F"
      parts << shell_quote("#{name}=@#{filename}")
    end

    # curl sets the multipart Content-Type (with boundary) itself when `-F`
    # is used; do not force urlencoded/json here.
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
