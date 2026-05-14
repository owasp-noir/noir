require "../../models/analyzer"
require "../../miniparsers/elixir_callee_extractor"

module Analyzer::Elixir
  abstract class ElixirEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    protected def attach_elixir_callees(endpoint : Endpoint, callees : Array(Noir::ElixirCalleeExtractor::Entry))
      Noir::ElixirCalleeExtractor.attach_to(endpoint, callees)
    end

    # No extension filter: Phoenix uses `.ex` only, Plug also accepts
    # `.exs`, so each analyzer filters inside `analyze_file`.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)

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
