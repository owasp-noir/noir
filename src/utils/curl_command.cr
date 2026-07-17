# Shared curl command construction used by the curl output builder and the
# HTML report's copy-as-curl feature.
module CurlCommand
  def self.shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
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

    headers.each do |header|
      parts << "-H"
      parts << shell_quote(header)
    end

    cookies.each do |cookie|
      parts << "--cookie"
      parts << shell_quote(cookie)
    end

    parts.join(" ")
  end
end
