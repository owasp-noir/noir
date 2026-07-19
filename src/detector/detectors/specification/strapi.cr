require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  # Strapi generates its REST surface from the content-type schemas the
  # Content-Type Builder writes to
  # `src/api/<name>/content-types/<name>/schema.json`, plus any custom
  # routes declared in `src/api/<name>/routes/*.{ts,js}`.
  #
  # Scoped to v4+. Strapi v3's `config/routes.json` is EOL since 2023 and
  # its shape is indistinguishable from an APISIX route export.
  class Strapi < Detector
    SCHEMA_FILENAME  = "schema.json"
    ROUTE_EXTENSIONS = {".ts", ".js", ".mts", ".cts", ".mjs", ".cjs"}

    # `"kind": "collectionType"` is a Strapi-only literal, and the
    # singular/plural name pair under `info` appears in no other schema
    # format.
    SCHEMA_MARKER = /"kind"\s*:\s*"(?:collectionType|singleType)"/

    # Strapi route objects always carry `handler`; Express/Fastify/
    # SvelteKit route modules never do.
    ROUTE_MARKER       = /\broutes\s*:\s*\[/
    ROUTE_HANDLER      = /\bhandler\s*:\s*['"]/
    CORE_ROUTER_MARKER = /\bcreateCoreRouter\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if schema_file?(filename)
        return detect_schema(filename, file_contents)
      end

      detect_routes(filename, file_contents)
    end

    # Memo safety: `applicable?` consults the path
    # (/content-types/ gate), not just the basename.
    def path_sensitive? : Bool
      true
    end

    def applicable?(filename : String) : Bool
      path = normalize(filename)
      return true if schema_file?(filename)
      return false unless ROUTE_EXTENSIONS.includes?(File.extname(path).downcase)

      routes_module?(path)
    end

    def set_name
      @name = "strapi"
    end

    # Registers every schema and route path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def detect_schema(filename : String, file_contents : String) : Bool
      return false unless file_contents.matches?(SCHEMA_MARKER)

      data = json_any?(file_contents)
      return false unless data
      root = data.as_h?
      return false unless root

      kind = root["kind"]?.try(&.as_s?)
      return false unless kind == "collectionType" || kind == "singleType"
      return false unless root["attributes"]?.try(&.as_h?)

      info = root["info"]?.try(&.as_h?)
      return false unless info
      return false unless info["singularName"]?.try(&.as_s?) || info["pluralName"]?.try(&.as_s?)

      CodeLocator.instance.push("strapi-schema", filename)
      true
    end

    private def detect_routes(filename : String, file_contents : String) : Bool
      core_router = file_contents.matches?(CORE_ROUTER_MARKER)
      custom = file_contents.matches?(ROUTE_MARKER) && file_contents.matches?(ROUTE_HANDLER)
      return false unless core_router || custom

      CodeLocator.instance.push("strapi-routes", filename)
      true
    end

    private def schema_file?(filename : String) : Bool
      return false unless File.basename(filename) == SCHEMA_FILENAME
      normalize(filename).includes?("/content-types/")
    end

    # A Strapi route module lives at `src/api/<name>/routes/<file>` (or
    # `<plugin>/server/routes/<file>`), so `/api/` must appear *before*
    # `/routes/`.
    #
    # The ordering is what rejects SvelteKit's `src/routes/api/foo/
    # +server.ts`, which contains both segments the other way round, and
    # any framework that merely keeps route modules in a `routes/`
    # directory.
    private def routes_module?(path : String) : Bool
      routes_at = path.rindex("/routes/")
      return false unless routes_at

      if api_at = path.index("/api/")
        return true if api_at < routes_at
      end

      # Plugin layout: `src/plugins/<name>/server/routes/<file>`.
      if server_at = path.index("/server/")
        return true if server_at < routes_at
      end

      false
    end

    private def normalize(filename : String) : String
      filename.includes?('\\') ? filename.gsub('\\', '/') : filename
    end
  end
end
