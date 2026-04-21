require "../../models/analyzer"
require "../../utils/utils.cr"

module Analyzer::Php
  abstract class PhpEngine < Analyzer
    def analyze
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)

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
