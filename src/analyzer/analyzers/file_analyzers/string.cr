require "../../../models/analyzer"


FileAnalyzer.add_hook(->(path : String, url : String) {
    begin
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          # TODO
        end
      end
    rescue
    end
  }
)
