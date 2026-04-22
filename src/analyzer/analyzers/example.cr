require "../../models/analyzer"

class AnalyzerExample < Analyzer
  def analyze
    # Source Analysis
    begin
      # Pull from the detector-built file_map (via FileHelper) so new
      # analyzers written against this template inherit subtree
      # pruning and --exclude-path filtering for free. Still restrict
      # to files below the analyzer's base_path — file_map spans the
      # union of every configured base_path, and an analyzer is
      # typically interested in one of them.
      base_dir_prefix = base_path.ends_with?("/") ? base_path : "#{base_path}/"
      all_files.each do |path|
        next unless path.starts_with?(base_dir_prefix) || path == base_path
        next unless File.exists?(path)
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line do |_line|
            # For example (Add endpoint to result)
            # endpoint = Endpoint.new("/", "GET")
            # details = Details.new(PathInfo.new(path, index + 1))
            # endpoint.details = details
            # @result << endpoint
          end
        end
      end
    rescue e
      logger.debug e
    end

    @result
  end
end
