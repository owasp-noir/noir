require "../../../models/analyzer"
require "../../../models/endpoint"
require "../../../utils/file_url_scanner"

# Reports plain `https?://…` literals found anywhere in the project whose
# rendered form contains the user-supplied `-u/--url`. This hook sees every
# file in the scan, so a candidate is only an endpoint once it survives the
# shared sanitising in `Noir::FileUrlScanner`: binary payload lines are
# dropped, and prose/markup delimiters are trimmed off the URL.
FileAnalyzer.add_hook(->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint
  return results if Noir::FileUrlScanner::REQUEST_FILE_EXTENSIONS.includes?(File.extname(path))

  begin
    Noir::FileUrlScanner.each_line(path) do |line, index|
      next if Noir::FileUrlScanner.binary_line?(line)

      Noir::FileUrlScanner.each_url(line) do |candidate|
        # One unparsable candidate must not abandon the rest of the file —
        # the previous file-wide rescue did exactly that.
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
  rescue
  end

  results
})
