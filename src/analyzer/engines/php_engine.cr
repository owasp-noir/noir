require "../../models/analyzer"
require "../../utils/utils.cr"

module Analyzer::Php
  abstract class PhpEngine < Analyzer
    # See AGENTS.md §"Two engine shapes" (and
    # docs/content/development/analyzer_architecture/) for when to override
    # `analyze_file` vs. `analyze` + `parallel_file_scan`.

    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # Walk the project tree concurrently and invoke the block for each
    # readable, non-directory file. PHP analyzers apply their own
    # extension/pathname filters inside the block because Symfony matches
    # `.php` *and* YAML route files, Laravel checks `routes/*.php`, etc.
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

    # Route composition helper. Will migrate to a PHP route extractor when that
    # layer is introduced; kept here for now so Laravel/CakePHP/Symfony stop
    # duplicating it.
    protected def build_full_path(prefix : String, path : String) : String
      return prefix if path == "/" && !prefix.empty?
      return path if prefix.empty?

      full_path = "/#{prefix.strip('/')}/#{path.strip('/')}"
      full_path = full_path.gsub(/\/+/, "/")
      full_path = full_path.chomp('/') if full_path.size > 1
      full_path
    end

    protected def extract_brace_path_params(route_path : String) : Array(Param)
      params = [] of Param
      route_path.scan(/\{(\w+)\??\}/).each do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end
  end
end
