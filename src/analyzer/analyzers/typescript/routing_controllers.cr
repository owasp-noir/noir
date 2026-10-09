require "./decorator_controller"

module Analyzer::Typescript
  # routing-controllers: `@JsonController('/users')` / `@Controller(...)` on
  # the class, `@Get('/:id')` on methods, `@Param`/`@QueryParam`/`@Body`/
  # `@HeaderParam`/`@CookieParam` on arguments. `routePrefix` passed to
  # `createExpressServer` / `useExpressServer` (or the Koa pair) prefixes
  # every controller.
  class RoutingControllers < DecoratorController
    analyzer_for "ts_routing_controllers"

    IMPORT_RE   = /(?:\bfrom|\brequire\s*\()\s*['"]routing-controllers['"]/
    CONTROLLERS = ["JsonController", "Controller"]
    PARAMS      = {
      "Param"         => {"path", nil},
      "QueryParam"    => {"query", nil},
      "QueryParams"   => {"query", "query"},
      "Body"          => {"body", "body"},
      "BodyParam"     => {"body", nil},
      "HeaderParam"   => {"header", nil},
      "HeaderParams"  => {"header", "headers"},
      "CookieParam"   => {"cookie", nil},
      "UploadedFile"  => {"body", nil},
      "UploadedFiles" => {"body", nil},
    } of String => Tuple(String, String?)
    PARAM_RE = param_decorator_re(PARAMS.keys)

    BOOTSTRAP_RE    = /\b(?:create|use)(?:Express|Koa)Server\s*\(/
    ROUTE_PREFIX_RE = /\broutePrefix\s*:\s*(['"`])([^'"`]+)\1/

    protected def controller_decorators : Array(String)
      CONTROLLERS
    end

    protected def app_root_markers : Array(String)
      ["\"routing-controllers\""]
    end

    private def extract_global_prefix_config(content : String, _path : String) : GlobalPrefixConfig?
      prefix_from_bootstrap(content, BOOTSTRAP_RE, ROUTE_PREFIX_RE)
    end
  end
end
