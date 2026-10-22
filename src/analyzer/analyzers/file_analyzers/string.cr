require "../../../models/analyzer"
require "../../../models/endpoint"
require "../../../utils/file_url_scanner"

# Reports plain `https?://…` literals found anywhere in the project that sit
# on the `-u/--url` origin, under its path. This hook sees every
# file in the scan, so a candidate is only an endpoint once it survives the
# shared sanitising in `Noir::FileUrlScanner`: binary payload lines are
# dropped, and prose/markup delimiters are trimmed off the URL.
# Attributed to `file_url`; see `FileAnalyzer::Hook` for why that name is not
# in the tech catalog.
FileAnalyzer.add_hook(tech: "file_url", func: ->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint
  # Parsed on the first candidate only: most files carry no URL literal.
  base = nil
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
        base ||= Noir::FileUrlScanner::BaseUrl.parse(url)
        endpoint_path = Noir::FileUrlScanner.path_under_base(parsed_url, base)
        next if endpoint_path.nil?

        details = Details.new(PathInfo.new(path, index + 1))
        results << Endpoint.new(endpoint_path, "GET", details)
      end
    end
  rescue
  end

  results
})
