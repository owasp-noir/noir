require "toml"
require "../../engines/javascript_engine"
require "../../engines/serverless_function_support"

module Analyzer::Javascript
  # Netlify Functions: each module in the functions directory
  # (`netlify/functions/` by default, or `[functions] directory` in
  # netlify.toml) is a function named after its file — `hello.mts`,
  # `hello/hello.mts` and `hello/index.mts` are all `hello`.
  #
  # A function answers at `config.path` when it sets one (a URLPattern
  # string or array, e.g. `/api/users/:id`) and only there; otherwise at
  # `/.netlify/functions/<name>`. `config.method` narrows the verbs.
  # Handlers are the modern default export `(req, context)` or the legacy
  # Lambda-style `export const handler = async (event) => ...`.
  #
  # Edge functions (`netlify/edge-functions/`) are routed only by an inline
  # `config.path` here; netlify.toml `[[edge_functions]]` declarations
  # belong to the `netlify` config analyzer. Scheduled functions take no
  # HTTP traffic and are skipped.
  class NetlifyFunctions < JavascriptEngine
    include ServerlessFunctionSupport

    analyzer_for "js_netlify_functions"

    EXTENSIONS       = [".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsx", ".tsx"]
    EDGE_KIND        = "edge-functions"
    FUNCTION_KIND    = "functions"
    DEFAULT_URL_BASE = "/.netlify/functions/"
    # v1 `export const handler = schedule("@hourly", async () => ...)`.
    SCHEDULE_WRAPPER_RE = /\bschedule\s*\(\s*['"`]/

    def analyze
      include_callee = callees_needed?
      configured = configured_function_dirs
      ordered_scan_files(get_files_by_extensions(EXTENSIONS)) do |path|
        kind, segments = function_location(path, configured) || next
        name = Noir::ServerlessLayout.netlify_function_name(segments) || next
        endpoints_for(path, read_file_content(path), kind, name, include_callee)
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    # `{kind, absolute_dir}` for every functions directory a netlify.toml
    # names (`[functions] directory`, legacy `[build] functions`,
    # `[build] edge_functions`), resolved against the toml's directory.
    private def configured_function_dirs : Array(Tuple(String, String))
      dirs = [] of Tuple(String, String)
      get_files_by_basename("netlify.toml").each do |path|
        base = File.dirname(path)
        doc = TOML.parse(read_file_content(path))
        build = doc["build"]?.try(&.as_h?)
        functions = doc["functions"]?.try(&.as_h?)
        {
          {FUNCTION_KIND, functions.try(&.["directory"]?).try(&.as_s?)},
          {FUNCTION_KIND, build.try(&.["functions"]?).try(&.as_s?)},
          {EDGE_KIND, build.try(&.["edge_functions"]?).try(&.as_s?)},
        }.each do |kind, dir|
          next if dir.nil? || dir.strip.empty?
          dirs << {kind, File.expand_path(dir.strip, base)}
        end
      rescue e
        @logger.debug "Netlify functions: failed to read #{path}: #{e.message}"
      end
      dirs.uniq
    end

    # `{kind, segments_below_the_functions_dir}`, or nil outside one.
    private def function_location(path : String, configured : Array(Tuple(String, String))) : Tuple(String, Array(String))?
      return if Noir::ServerlessLayout.non_handler_file?(path)
      location = configured_location(path, configured)
      location ||= Noir::ServerlessLayout.netlify_default_remainder(path, base_relative_path(path)).try do |kind, _, segments|
        {kind, segments}
      end
      return unless location
      return if location[1].any?(&.==("node_modules"))
      location
    end

    private def configured_location(path : String, configured : Array(Tuple(String, String))) : Tuple(String, Array(String))?
      expanded = File.expand_path(path)
      configured.each do |kind, dir|
        prefix = dir.ends_with?('/') ? dir : "#{dir}/"
        next unless expanded.starts_with?(prefix)
        return {kind, expanded[prefix.size..].split('/').reject(&.empty?)}
      end
      nil
    end

    private def endpoints_for(path : String, content : String, kind : String, name : String, include_callee : Bool) : Array(Endpoint)
      extractor = Noir::JSServerlessFunctionExtractor
      config = extractor.config_object(content) || ""
      paths = extractor.config_strings(config, "path")
      return [] of Endpoint if paths.empty? && extractor.config_key?(config, "schedule")

      handler = extractor.default_handler(content)
      style = :request
      unless handler
        handler = extractor.exported_handler(content, "handler") || return [] of Endpoint
        return [] of Endpoint if content.matches?(SCHEDULE_WRAPPER_RE)
        style = :lambda
      end

      if paths.empty?
        # An edge function without an inline path is wired up in
        # netlify.toml, which the `netlify` analyzer reads.
        return [] of Endpoint if kind == EDGE_KIND
        paths = ["#{DEFAULT_URL_BASE}#{name}"]
      end

      methods = extractor.config_strings(config, "method").map(&.upcase).select do |verb|
        Noir::JSServerlessFunctionExtractor::KNOWN_METHODS.includes?(verb)
      end.uniq!
      methods = catch_all_methods(handler) if methods.empty?

      paths.uniq.flat_map do |url|
        methods.map { |verb| serverless_endpoint(url, verb, path, handler, style, include_callee) }
      end
    end
  end
end
