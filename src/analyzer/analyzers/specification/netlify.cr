require "../../../models/analyzer"
require "toml"

module Analyzer::Specification
  class Netlify < Analyzer
    DEFAULT_METHOD = "ANY"

    def analyze
      locator = CodeLocator.instance
      redirects_files = locator.all("netlify-redirects")
      toml_files = locator.all("netlify-toml")

      redirects_files.each do |path|
        next unless File.exists?(path)
        parse_redirects_file(path)
      end

      toml_files.each do |path|
        next unless File.exists?(path)
        parse_toml_file(path)
      end

      @result
    end

    private def parse_redirects_file(path : String)
      lines = File.read_lines(path)
      lines.each_with_index do |line, index|
        stripped = line.strip
        next if stripped.empty?
        next if stripped.starts_with?('#')

        fields = stripped.split(/\s+/, remove_empty: true)
        next if fields.size < 2

        add_endpoint(fields[0], path, index + 1)
      end
    rescue e
      @logger.debug "Netlify analyzer failed to parse redirects file #{path}"
      @logger.debug_sub e
    end

    private def parse_toml_file(path : String)
      doc = TOML.parse_file(path)

      if redirects = doc["redirects"]?
        redirects.as_a?.try do |items|
          items.each do |item|
            if from = item["from"]?.try(&.as_s?)
              add_endpoint(from, path, nil) unless from.empty?
            end
          end
        end
      end

      if edge_functions = doc["edge_functions"]?
        edge_functions.as_a?.try do |items|
          items.each do |item|
            if route_path = item["path"]?.try(&.as_s?)
              add_endpoint(route_path, path, nil) unless route_path.empty?
            end
          end
        end
      end
    rescue e
      @logger.debug "Netlify analyzer failed to parse TOML file #{path}"
      @logger.debug_sub e
    end

    private def add_endpoint(route : String, source : String, line : Int32?)
      details = if line
                  Details.new(PathInfo.new(source, line))
                else
                  Details.new(PathInfo.new(source))
                end
      @result << Endpoint.new(route, DEFAULT_METHOD, details)
    end
  end
end
