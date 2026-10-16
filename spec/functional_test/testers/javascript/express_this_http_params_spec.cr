require "../../func_spec.cr"

# A controller on a local base class (`this.get('/tags', this.getTags)`) and an
# app handed to a function as `http` are served routes; the API-client class,
# Node/k6/sails.io/Angular client calls beside them are not.
FunctionalTester.new("fixtures/javascript/express_this_http_params/", {
  :techs     => 1,
  :endpoints => 7,
}, [
  Endpoint.new("/health", "GET", [] of Param),
  Endpoint.new("/ping", "GET", [] of Param),
  Endpoint.new("/echo", "POST", [] of Param),
  Endpoint.new("/tags", "GET", [] of Param),
  Endpoint.new("/tags", "POST", [] of Param),
  Endpoint.new("/tags/:name", "PUT", [Param.new("name", "", "path")]),
  Endpoint.new("/tags/:name", "DELETE", [Param.new("name", "", "path")]),
]).perform_tests
