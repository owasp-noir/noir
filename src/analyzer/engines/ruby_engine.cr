require "../../models/analyzer"
require "../../miniparsers/ruby_callee_extractor"

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

    # Locate the directories that host a known framework anchor file
    # (e.g. `config/routes.rb`) anywhere under `base_paths`. Returns the
    # framework root for each match, i.e. the anchor's path with the
    # relative suffix stripped. Lets analyzers stop assuming the framework
    # root is `@base_path` and survive monorepos where it lives in a
    # subdirectory (`App/`, `backend/`, ...).
    protected def discover_framework_roots(anchor : String) : Array(String)
      suffix = anchor.starts_with?("/") ? anchor : "/#{anchor}"
      roots = [] of String

      all_files.each do |file|
        next unless file.ends_with?(suffix)
        next unless base_paths.any? do |base|
                      prefix = base.ends_with?("/") ? base : "#{base}/"
                      file.starts_with?(prefix) || file == "#{base}#{suffix}"
                    end

        root = file[0, file.size - suffix.size]
        roots << root unless roots.includes?(root)
      end

      roots
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

    protected def attach_ruby_callees(endpoint : Endpoint, callees : Array(Noir::RubyCalleeExtractor::Entry))
      Noir::RubyCalleeExtractor.attach_to(endpoint, callees)
    end
  end
end
