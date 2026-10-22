require "./decorator_controller"

module Analyzer::Typescript
  # inversify-express-utils: `@controller("/users")` on the class,
  # `@httpGet("/:id")` / `@httpPost(...)` / `@all(...)` on methods,
  # `@requestParam`/`@queryParam`/`@requestBody`/`@requestHeaders`/`@cookies`
  # on arguments. `rootPath` in the `InversifyExpressServer` options
  # prefixes every controller.
  class Inversify < DecoratorController
    analyzer_for "ts_inversify"

    IMPORT_RE   = /(?:\bfrom|\brequire\s*\()\s*['"]inversify-express-utils['"]/
    CONTROLLERS = ["controller"]
    ROUTES      = {
      "httpGet"     => ["GET"],
      "httpPost"    => ["POST"],
      "httpPut"     => ["PUT"],
      "httpPatch"   => ["PATCH"],
      "httpDelete"  => ["DELETE"],
      "httpHead"    => ["HEAD"],
      "httpOptions" => ["OPTIONS"],
      "all"         => ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"],
    }
    ROUTE_RE = /@(httpGet|httpPost|httpPut|httpPatch|httpDelete|httpHead|httpOptions|all)\s*\(/
    PARAMS   = {
      "requestParam"   => {"path", nil},
      "queryParam"     => {"query", nil},
      "requestBody"    => {"body", "body"},
      "requestHeaders" => {"header", nil},
      "cookies"        => {"cookie", nil},
    } of String => Tuple(String, String?)
    PARAM_RE = param_decorator_re(PARAMS.keys)

    BOOTSTRAP_RE = /\bnew\s+InversifyExpressServer\s*\(/
    ROOT_PATH_RE = /\brootPath\s*:\s*(['"`])([^'"`]+)\1/

    protected def controller_decorators : Array(String)
      CONTROLLERS
    end

    protected def route_decorator_methods : Hash(String, Array(String))
      ROUTES
    end

    protected def route_decorator_re : Regex
      ROUTE_RE
    end

    protected def app_root_markers : Array(String)
      ["\"inversify-express-utils\""]
    end

    private def extract_global_prefix_config(content : String, _path : String) : GlobalPrefixConfig?
      prefix_from_bootstrap(content, BOOTSTRAP_RE, ROOT_PATH_RE)
    end
  end
end
