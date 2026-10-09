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

    # Line shapes `parse_toml_fallback` reads. Any `[...]` / `[[...]]` line is
    # a header, quoted keys (`[context."deploy-preview"]`) included, so a
    # table the scan does not read always ends the one before it.
    TOML_TABLE_HEADER_RE      = /\A\s*\[\[?([^\]]*)\]/
    TOML_STRING_ASSIGNMENT_RE = /\A\s*([A-Za-z_]+)\s*=\s*"([^"]*)"/

    def analyze
      each_spec_file(Noir::LocatorKeys::NETLIFY_REDIRECTS) do |path|
        parse_redirects_file(path)
      end

      each_spec_file(Noir::LocatorKeys::NETLIFY_TOML) do |path|
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
      # `read_file_content`, not `TOML.parse_file`: a BOM or UTF-16 file is
      # only decoded on noir's read path, and re-reading the raw bytes lost
      # every rule in it without a trace.
      content = read_file_content(path)
      doc = begin
        TOML.parse(content)
      rescue e
        # The bundled TOML shard predates TOML 1.0 and refuses e.g. `0xFF`
        # or an integer beyond Int64 anywhere in the file. Recover the rules
        # by a line scan rather than losing all of them.
        @logger.debug "Netlify TOML parse failed for #{path}, falling back to a line scan: #{e}"
        parse_toml_fallback(content, path)
        return
      end

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
    end

    # `from = "..."` under a `[[…redirects]]` table and `path = "..."` under
    # a `[[…edge_functions]]` table, top-level or in a context override.
    private def parse_toml_fallback(content : String, path : String)
      key = nil
      content.each_line do |line|
        if header = line.match(TOML_TABLE_HEADER_RE)
          key = case header[1].delete(%("')).split('.').last?.try(&.strip)
                when "redirects"      then "from"
                when "edge_functions" then "path"
                end
        elsif key && (assignment = line.match(TOML_STRING_ASSIGNMENT_RE)) && assignment[1] == key
          add_endpoint(assignment[2], path, nil) unless assignment[2].empty?
        end
      end
    end

    private def collect_redirects(node : TOML::Any?, path : String)
      node.try(&.as_a?).try do |items|
        items.each do |item|
          if from = item.as_h?.try(&.["from"]?).try(&.as_s?)
            add_endpoint(from, path, nil) unless from.empty?
          end
        end
      end
    end

    private def collect_edge_functions(node : TOML::Any?, path : String)
      node.try(&.as_a?).try do |items|
        items.each do |item|
          if route_path = item.as_h?.try(&.["path"]?).try(&.as_s?)
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
