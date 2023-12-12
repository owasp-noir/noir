require "../../../models/analyzer"
require "../../../models/endpoint"

FileAnalyzer.add_hook(->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint

  begin
    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
      file.each_line do |line|
        url_match = line.match(/\A(https?:\/\/[^\s]+)/)
        if url_match
          parsed_url = URI.parse(url_match[1])
          if parsed_url.to_s.includes? url
            results << Endpoint.new(parsed_url.path, "GET")
          end
        end
      end
    end
  rescue
  end

  results
})
