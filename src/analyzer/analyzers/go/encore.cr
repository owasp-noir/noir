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
    MIDDLEWARE    = /^[ \t]*\/\/encore:middleware\b[^\n]*/m

    def analyze
      sources = read_package_file_contents
      dirs = sources.compact_map { |path, content| File.dirname(path) if content.includes?(Noir::EncoreExtractor::GO_DIRECTIVE) }.to_set
      paths = sources.keys.select { |path| dirs.includes?(File.dirname(path)) }
      middleware = sources.values.flat_map(&.scan(MIDDLEWARE).map(&.[0].strip))

      parsed = ordered_parallel_analyze(paths) { |path| {path, Noir::EncoreExtractor.extract_go(sources[path])} }
      structs = Hash(String, Hash(String, Array(Noir::EncoreExtractor::GoField))).new
      parsed.each do |path, file|
        package = structs[File.dirname(path)] ||= Hash(String, Array(Noir::EncoreExtractor::GoField)).new
        file.structs.each { |name, fields| package[name] ||= fields }
      end

      parsed.each do |path, file|
        package_name = file.package || File.basename(File.dirname(path))
        file.apis.each { |api| emit(api, path, package_name, structs[File.dirname(path)], middleware, result) }
      end
      result
    end

    private def emit(api : Noir::EncoreExtractor::GoApi, path : String, package_name : String,
                     structs : Hash(String, Array(Noir::EncoreExtractor::GoField)), middleware : Array(String),
                     result : Array(Endpoint))
      raw = api.options.includes?("raw")
      access = api.options.find(&.in?("public", "private", "auth")) || "private"
      url, path_names = Noir::EncoreExtractor.route(api.fields["path"]? || "/#{package_name}.#{api.name}")

      # Context, then one argument per path param, then the request struct.
      # A package-qualified type (`*shared.Req`) is not in this package's table.
      has_request = !raw && api.params.size > path_names.size + 1
      request = structs[api.params.last.lchop('*')]? if has_request

      access_requires = requires(access, api, path, middleware)
      methods = api.fields["method"]?.try(&.split(',')) || (raw ? ["*"] : (has_request ? ["POST"] : ["GET", "POST"]))
      methods.each do |method|
        method = "ANY" if method == "*"
        endpoint = Endpoint.new(url, method, Details.new(PathInfo.new(path, api.line)))
        path_names.each { |name| endpoint.push_param(Param.new(name, "", "path")) }
        request.try &.each { |field| push_field(endpoint, field) }
        endpoint.add_tag(Tag.new("encore-access", access == "private" ? "private" : "public", TAGGER, requires: access_requires))
        if access == "auth"
          endpoint.add_tag(Tag.new("auth", "Encore auth endpoint", TAGGER, requires: [Access::Clause.new([Access::Atom.new(:authenticated)], "//encore:api auth", path, api.line)]))
        end
        result << endpoint
      end
    end

    # `auth` runs the app's auth handler first and refuses a caller it does
    # not authenticate; `private` is reachable only from the app's own
    # services. A `//encore:middleware` whose target selects the endpoint
    # (`all`, or a `tag:` the directive lists) runs after that and may
    # refuse anyone.
    # ponytail: a service-local middleware is applied app-wide (never wider:
    # its clause only adds an unknown).
    private def requires(access : String, api : Noir::EncoreExtractor::GoApi, path : String, middleware : Array(String)) : Array(Access::Clause)
      source = "//encore:api #{access}"
      clause = case access
               when "public" then Access::Clause.new([Access::Atom.new(:anonymous)], source, path, api.line)
               when "auth"   then Access::Clause.new([Access::Atom.new(:authenticated)], source, path, api.line)
               else               Access::Clause.unresolved("private", source, path, api.line)
               end
      applied = middleware.select do |directive|
        targets = directive.match(/\btarget=(\S+)/).try(&.[1].split(',')) || ["all"]
        targets.any? { |target| target == "all" || api.options.includes?(target) }
      end
      [clause] + applied.map { |directive| Access::Clause.unresolved(directive, directive) }
    end

    # Encore's request encoding: a `header`/`query`/`qs` tag places the
    # field; otherwise GET/HEAD/DELETE send it as a query param and every
    # other method as a JSON body field. The wire name is that location's
    # tag (`-` drops the field), else snake_case for query and the field
    # name for the rest.
    private def push_field(endpoint : Endpoint, field : Noir::EncoreExtractor::GoField)
      return unless field.name[0].uppercase?
      tags = field.tag.scan(TAG_RE).to_h { |m| {m[1], m[2].split(',').first} }

      location, keys = if tags.has_key?("header")
                         {"header", %w[header]}
                       elsif tags.has_key?("query") || tags.has_key?("qs") || QUERY_METHODS.includes?(endpoint.method)
                         {"query", %w[query qs]}
                       else
                         {"json", %w[json]}
                       end
      name = keys.compact_map { |key| tags[key]? }.first?
      return if name == "-"
      endpoint.push_param(Param.new(name.presence || (location == "query" ? field.name.underscore : field.name), "", location))
    end
  end
end
