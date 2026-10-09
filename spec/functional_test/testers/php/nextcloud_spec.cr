require "../../func_spec.cr"

# `appinfo/routes.php` routes/resources live under `/apps/<id>`, OCS ones
# under `/ocs/v2.php/apps/<id>`; `#[FrontpageRoute]` / `#[ApiRoute]` take
# the same prefixes. Split route files under `appinfo/routes/` are read, a
# non-core app's `root` is ignored, and commented-out attributes are not
# routes. The app's own `.php` files are not URLs (no php_pure
# file-path endpoints).
FunctionalTester.new("fixtures/php/nextcloud/", {
  :techs     => 2,
  :endpoints => 11,
}, [
  Endpoint.new("/apps/notes/", "GET"),
  Endpoint.new("/apps/notes/home", "GET"),
  Endpoint.new("/ocs/v2.php/apps/notes/api/v1/share/{token}", "DELETE", [
    Param.new("token", "", "path"), Param.new("shareWith", "", "query"), Param.new("permissions", "", "query"),
  ]),
  Endpoint.new("/apps/notes/notes/{id}", "PUT", [Param.new("id", "", "path"), Param.new("content", "", "form")]),
  Endpoint.new("/ocs/v2.php/apps/notes/api/v1/share", "POST", [
    Param.new("shareWith", "", "form"), Param.new("permissions", "", "form"),
  ]),
  Endpoint.new("/apps/notes/notes", "GET", [Param.new("category", "", "query")]),
  Endpoint.new("/apps/notes/notes", "POST", [Param.new("title", "", "form"), Param.new("content", "", "form")]),
  Endpoint.new("/apps/notes/notes/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/apps/notes/notes/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/ocs/v2.php/apps/notes/api/{apiVersion}/notes/{id}", "GET", [
    Param.new("apiVersion", "", "path"), Param.new("id", "", "path"),
  ]),
  Endpoint.new("/apps/notes/settings", "POST", [Param.new("defaultFolder", "", "form")]),
]).perform_tests
