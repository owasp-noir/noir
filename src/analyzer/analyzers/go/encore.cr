require "../../engines/go_engine"
require "../../../miniparsers/encore_extractor"

module Analyzer::Go
  # Encore (https://encore.dev/docs/go/primitives/defining-apis) declares
  # every endpoint with a `//encore:api` directive on its handler:
  #
  #   //encore:api public method=GET path=/users/:id
  #   func GetUser(ctx context.Context, id int, p *Params) (*User, error)
  #
  # Path parameters bind to the handler's leading arguments in order; a
  # further argument is the request struct, whose fields are header/query
  # params by tag and otherwise query (GET/HEAD/DELETE) or JSON body.
  class Encore < GoEngine
    analyzer_for "go_encore"

    TAGGER        = "encore_analyzer"
    QUERY_METHODS = %w[GET HEAD DELETE]
    TAG_RE        = /(\w+):"([^"]*)"/
    PACKAGE_RE    = /^package\s+(\w+)/m

    def analyze
      sources = read_package_file_contents
      dirs = sources.compact_map { |path, content| File.dirname(path) if content.includes?(Noir::EncoreExtractor::GO_DIRECTIVE) }.to_set
      paths = sources.keys.select { |path| dirs.includes?(File.dirname(path)) }

      parsed = ordered_parallel_analyze(paths) { |path| {path, Noir::EncoreExtractor.extract_go(sources[path])} }
      structs = Hash(String, Hash(String, Array(Noir::EncoreExtractor::GoField))).new
      parsed.each do |path, (_, file_structs)|
        package = structs[File.dirname(path)] ||= Hash(String, Array(Noir::EncoreExtractor::GoField)).new
        file_structs.each { |name, fields| package[name] ||= fields }
      end

      parsed.each do |path, (apis, _)|
        next if apis.empty?
        package_name = sources[path].match(PACKAGE_RE).try(&.[1]) || File.basename(File.dirname(path))
        apis.each { |api| emit(api, path, package_name, structs[File.dirname(path)], result) }
      end
      result
    end

    private def emit(api : Noir::EncoreExtractor::GoApi, path : String, package_name : String,
                     structs : Hash(String, Array(Noir::EncoreExtractor::GoField)), result : Array(Endpoint))
      raw = api.options.includes?("raw")
      access = api.options.find { |o| o.in?("public", "private", "auth") } || "private"
      url, path_names = Noir::EncoreExtractor.route(api.fields["path"]? || "/#{package_name}.#{api.name}")

      request = nil
      if !raw && api.params.size > path_names.size + 1
        request = structs[api.params.last.lchop('*').split('.').last]?
      end

      methods = api.fields["method"]?.try(&.split(',')) || (raw ? ["*"] : (api.params.size > path_names.size + 1 ? ["POST"] : ["GET", "POST"]))
      methods.each do |method|
        method = "ANY" if method == "*"
        endpoint = Endpoint.new(url, method, Details.new(PathInfo.new(path, api.line)))
        path_names.each { |name| endpoint.push_param(Param.new(name, "", "path")) }
        request.try &.each { |field| push_field(endpoint, field) }
        endpoint.add_tag(Tag.new("encore-access", access == "private" ? "private" : "public", TAGGER))
        endpoint.add_tag(Tag.new("auth", "Encore auth endpoint", TAGGER)) if access == "auth"
        result << endpoint
      end
    end

    # Encore's request encoding: a `header`/`query`/`qs` tag places the
    # field; otherwise GET/HEAD/DELETE send it as a snake_case query param
    # and every other method as a JSON body field.
    private def push_field(endpoint : Endpoint, field : Noir::EncoreExtractor::GoField)
      return unless field.name[0].uppercase?
      tags = field.tag.scan(TAG_RE).to_h { |m| {m[1], m[2].split(',').first} }
      return if tags.any? { |key, name| name == "-" && key.in?("header", "query", "qs", "json") }

      param = if name = tags["header"]?
                Param.new(name, "", "header")
              elsif name = tags["query"]? || tags["qs"]?
                Param.new(name, "", "query")
              elsif QUERY_METHODS.includes?(endpoint.method)
                Param.new(field.name.underscore, "", "query")
              else
                Param.new(tags["json"]?.presence || field.name, "", "json")
              end
      endpoint.push_param(param)
    end
  end
end
