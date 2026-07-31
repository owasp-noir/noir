require "base64"
require "../../../models/analyzer"
require "../../../models/endpoint"
require "../../../utils/file_url_scanner"

# Reports URLs hidden in base64-encoded literals whose decoded form contains
# the user-supplied `-u/--url`.
FileAnalyzer.add_hook(->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint

  begin
    Noir::FileUrlScanner.each_line(path) do |line, index|
      next if Noir::FileUrlScanner.binary_line?(line)

      # Every token on the line is tried, not just the first: a line
      # carrying an unrelated base64 blob before the encoded URL used to
      # hide it. And a token that is not valid base64 raises out of
      # `decode_string` — that exception used to escape the per-file rescue
      # and silently abandon every remaining line of the file.
      line.scan(Noir::FileUrlScanner::BASE64_TOKEN_RE) do |token|
        decoded = begin
          Base64.decode_string(token[0])
        rescue
          next
        end

        Noir::FileUrlScanner.each_url(decoded) do |candidate|
          parsed_url = begin
            URI.parse(candidate)
          rescue
            nil
          end
          next if parsed_url.nil?
          next unless parsed_url.to_s.includes? url

          details = Details.new(PathInfo.new(path, index + 1))
          results << Endpoint.new(parsed_url.path, "GET", details)
        end
      end
    end
  rescue
  end

  results
})
