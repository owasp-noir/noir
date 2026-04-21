require "../../models/analyzer"

module Analyzer::Scala
  abstract class ScalaEngine < Analyzer
    def analyze
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".scala"

          begin
            result.concat(analyze_file(path))
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end

      Fiber.yield
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)
  end
end
