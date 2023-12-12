require "../../../models/analyzer"
require "../../../models/endpoint"

FileAnalyzer.add_hook(->(path : String, _url : String) : Array(Endpoint) {
  results = [] of Endpoint

  begin
    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
      file.each_line do |_|
        # TODO
        # e.g
        # results << Endpoint.new("/", "GET",)
      end
    end
  rescue
  end

  results
})
