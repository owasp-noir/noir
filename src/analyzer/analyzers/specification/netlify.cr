require "../../engines/specification_engine"
require "toml"

module Analyzer::Specification
  class Netlify < SpecificationEngine
    analyzer_for "netlify"

    DEFAULT_METHOD = "ANY"

    # A `_redirects` / `netlify.toml` source may be a bare path (`/blog/*`) or a
    # fully-qualified URL for a domain-level rule
    # (`https://old.example.com/*  https://new.example.com/:splat  301!`).
    ABSOLUTE_SOURCE_RE = /\A[a-z][a-z0-9+.-]*:\/\/([^\/]+)(\/.*)?\z/i

    def analyze
      each_spec_file("netlify-redirects") do |path|
        parse_redirects_file(path)
      end

      each_spec_file("netlify-toml") do |path|
        parse_toml_file(path)
      end

      @result
    end

    private def parse_redirects_file(path : String)
      content = read_file_content(path)
      content.each_line.with_index do |line, index|
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

      collect_redirects(doc["redirects"]?, path)
      collect_edge_functions(doc["edge_functions"]?, path)

      # Context overrides (`[[context.production.redirects]]`,
      # `[[context.deploy-preview.redirects]]`, …) carry rules that exist only
      # for that deploy context but are just as reachable once deployed.
      if contexts = doc["context"]?.try(&.as_h?)
        contexts.each_value do |ctx|
          next unless ctx_h = ctx.as_h?
          collect_redirects(ctx_h["redirects"]?, path)
          collect_edge_functions(ctx_h["edge_functions"]?, path)
        end
      end
    rescue e
      @logger.debug "Netlify analyzer failed to parse TOML file #{path}"
      @logger.debug_sub e
    end

    private def collect_redirects(node : TOML::Any?, path : String)
      node.try(&.as_a?).try do |items|
        items.each do |item|
          if from = item["from"]?.try(&.as_s?)
            add_endpoint(from, path, nil) unless from.empty?
          end
        end
      end
    end

    private def collect_edge_functions(node : TOML::Any?, path : String)
      node.try(&.as_a?).try do |items|
        items.each do |item|
          if route_path = item["path"]?.try(&.as_s?)
            add_endpoint(route_path, path, nil) unless route_path.empty?
          end
        end
      end
    end

    private def add_endpoint(route : String, source : String, line : Int32?)
      host, path = split_source(route)
      return if path.nil?

      details = if line
                  Details.new(PathInfo.new(source, line))
                else
                  Details.new(PathInfo.new(source))
                end
      endpoint = Endpoint.new(path, DEFAULT_METHOD, details)
      endpoint.add_tag(Tag.new("netlify-host", host, "netlify_analyzer")) if host
      @result << endpoint
    end

    # A scheme-qualified source names another host; the scheme and host are not
    # part of the request path, so keeping them inline produced URLs like
    # `http://https://old.example.com/*`. Split the host into a tag and emit the
    # path. A source without a scheme is left alone — including the slash-less
    # `geps/by-state/` form that turns up in real `_redirects` files — because
    # there is no way to tell a relative path from a host name there.
    private def split_source(route : String) : Tuple(String?, String?)
      trimmed = route.strip
      return {nil, trimmed} unless trimmed.includes?("://")

      if m = ABSOLUTE_SOURCE_RE.match(trimmed)
        return {m[1], m[2]? || "/"}
      end

      {nil, nil}
    end
  end
end
