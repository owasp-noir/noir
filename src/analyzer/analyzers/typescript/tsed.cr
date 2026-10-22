require "./decorator_controller"

module Analyzer::Typescript
  # Ts.ED: `@Controller("/calendars")` (`@tsed/di`, older `@tsed/common`),
  # `@Get("/:id")` (`@tsed/schema`), `@PathParams`/`@QueryParams`/
  # `@BodyParams`/`@HeaderParams`/`@Cookies` on arguments. The server's
  # `@Configuration({ mount: { "/rest": [...] } })` prefixes the controllers.
  class Tsed < DecoratorController
    analyzer_for "ts_tsed"

    IMPORT_RE = /(?:\bfrom|\brequire\s*\()\s*['"]@tsed\/(?:common|schema|di|platform-)/
    PARAMS    = {
      "PathParams"     => {"path", nil},
      "RawPathParams"  => {"path", nil},
      "QueryParams"    => {"query", nil},
      "RawQueryParams" => {"query", nil},
      "BodyParams"     => {"body", "body"},
      "RawBodyParams"  => {"body", "body"},
      "HeaderParams"   => {"header", nil},
      "Cookies"        => {"cookie", nil},
      "CookiesParams"  => {"cookie", nil},
      "MultipartFile"  => {"body", nil},
    } of String => Tuple(String, String?)
    PARAM_RE = param_decorator_re(PARAMS.keys)

    BOOTSTRAP_RE = /@(?:Configuration|ServerSettings)\s*\(/
    MOUNT_RE     = /\bmount\s*:\s*\{\s*(['"`])([^'"`]+)\1\s*:/

    protected def app_root_markers : Array(String)
      ["\"@tsed/"]
    end

    # ponytail: only the first `mount` key is read; a server mounting
    # different controller sets under several prefixes puts them all under
    # the first. Map each key's controller list if that shape shows up.
    private def extract_global_prefix_config(content : String, _path : String) : GlobalPrefixConfig?
      prefix_from_bootstrap(content, BOOTSTRAP_RE, MOUNT_RE)
    end
  end
end
