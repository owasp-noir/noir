require "../../models/analyzer"

module Analyzer::Crystal
  abstract class CrystalEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `.cr` extension filter plus `lib/` exclusion baked in (shards puts
    # dependencies under `lib/` and we don't want to analyze them).
    # Subclasses that need a custom scan shape can override `analyze`
    # (e.g. Amber/Kemal run a public-dir post-pass after the file walk).
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".cr"
          next if path.includes?("lib")

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end
  end
end
