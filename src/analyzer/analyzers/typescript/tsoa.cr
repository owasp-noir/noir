require "json"
require "./decorator_controller"

module Analyzer::Typescript
  # tsoa: `@Route("users")` on a class extending `Controller`, `@Get("{id}")`
  # on methods, `@Path`/`@Query`/`@Body`/`@Header` on arguments. The server
  # prefix is `routes.basePath` (or `spec.basePath`) in `tsoa.json`.
  class Tsoa < DecoratorController
    analyzer_for "ts_tsoa"

    IMPORT_RE   = /(?:\bfrom|\brequire\s*\()\s*['"](?:tsoa|@tsoa\/runtime)['"]/
    CONTROLLERS = ["Route"]
    PARAMS      = {
      "Path"          => {"path", nil},
      "Query"         => {"query", nil},
      "Header"        => {"header", nil},
      "Body"          => {"body", "body"},
      "BodyProp"      => {"body", nil},
      "FormField"     => {"body", nil},
      "UploadedFile"  => {"body", nil},
      "UploadedFiles" => {"body", nil},
    } of String => Tuple(String, String?)
    PARAM_RE = param_decorator_re(PARAMS.keys)

    def analyze
      endpoints = analyze_with_extensions([".ts"])
      configs = get_files_by_basename("tsoa.json").compact_map do |path|
        base_path_config(path).try { |config| {path, config} }
      end
      apply_global_prefixes(endpoints, configs)
      strip_trailing_slashes(endpoints)
    end

    def import_re : Regex
      IMPORT_RE
    end

    def param_decorators : ParamDecorators
      PARAMS
    end

    def param_decorator_re : Regex
      PARAM_RE
    end

    protected def controller_decorators : Array(String)
      CONTROLLERS
    end

    protected def app_root_markers : Array(String)
      ["\"tsoa\"", "\"@tsoa/runtime\""]
    end

    # `{id}` in the route is a path param even without `@Path()`: tsoa
    # matches undecorated arguments to the template by name.
    private def extract_path_parameters(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) { |match| endpoint.push_param(Param.new(match[1], "", "path")) }
    end

    private def base_path_config(path : String) : GlobalPrefixConfig?
      json = JSON.parse(read_file_content(path))
      base = json.dig?("routes", "basePath").try(&.as_s?) || json.dig?("spec", "basePath").try(&.as_s?)
      GlobalPrefixConfig.new(base, [] of GlobalPrefixExclude) if base
    rescue # unreadable, invalid, or not an object at the top
      nil
    end
  end
end
