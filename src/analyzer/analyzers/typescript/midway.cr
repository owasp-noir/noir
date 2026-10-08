require "../javascript/nestjs"

module Analyzer::Typescript
  # Midway (`@midwayjs/core`, v2 `@midwayjs/decorator`) routes with the same
  # decorator model as NestJS — `@Controller(prefix)` on the class, `@Get`,
  # `@Post`, `@Del`, … on methods, `@Query`/`@Param`/`@Body`/`@Headers` on
  # arguments — so it reuses the Nest parser and only claims the files that
  # import from `@midwayjs/*`.
  class Midway < Analyzer::Javascript::Nestjs
    analyzer_for "ts_midway"

    # `koa: { globalPrefix: '/api' }` (or `express:`/`egg:`) in the base
    # config. Per-environment files (`config.prod.ts`, …) are overlays and
    # are not read.
    GLOBAL_PREFIX_RE = /\bglobalPrefix\s*:\s*(['"`])([^'"`]+)\1/

    def analyze
      # Midway joins prefix and path with `joinURLPath`, which drops the
      # trailing slash: `@Controller('/users')` + `@Get('/')` is `/users`.
      analyze_with_extensions([".ts"]).map do |endpoint|
        endpoint.url = endpoint.url.rstrip('/') if endpoint.url.size > 1
        endpoint
      end
    end

    protected def owns_source?(content : String) : Bool
      content.includes?(MIDWAY_IMPORT)
    end

    # Scopes each app's `globalPrefix` to its own package.json in a monorepo.
    protected def app_root_markers : Array(String)
      ["@midwayjs/core", "@midwayjs/decorator"]
    end

    # ponytail: `ignoreGlobalPrefix: true` on a controller or route is not
    # honoured; those routes get the prefix too.
    private def extract_global_prefix_config(content : String, path : String) : GlobalPrefixConfig?
      return unless File.basename(path).starts_with?("config.default.")
      if match = content.match(GLOBAL_PREFIX_RE)
        GlobalPrefixConfig.new(match[2], [] of GlobalPrefixExclude)
      end
    end
  end
end
