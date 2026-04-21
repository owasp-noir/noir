require "../../models/analyzer"

module Analyzer::Ruby
  abstract class RubyEngine < Analyzer
    HTTP_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # Match the `<verb> "<path>"` idiom on a single line and return the first
    # endpoint found, or an empty endpoint if none match. Shared by Hanami
    # and Sinatra (Rails uses a different per-line-multi-match shape).
    def line_to_endpoint(content : String, details : Details? = nil) : Endpoint
      HTTP_VERBS.each do |verb|
        content.scan(/#{verb}\s+['"](.+?)['"]/) do |match|
          if match.size > 1
            if details
              return Endpoint.new(match[1], verb.upcase, details)
            else
              return Endpoint.new(match[1], verb.upcase)
            end
          end
        end
      end
      Endpoint.new("", "")
    end

    # Walk the project file tree in parallel, invoking the block for each
    # readable non-directory file. Used by analyzers that scan the whole
    # tree (Sinatra); Rails/Hanami target specific config files directly.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
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
