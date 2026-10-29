require "../../func_spec.cr"

# cadwyn's `VersionedAPIRouter` subclasses `fastapi.APIRouter`: its routes
# are served, its prefix stays its own (it used to land on the file's one
# known router), and a `VersionedAPIRouter` parent passes its prefix down.
FunctionalTester.new("fixtures/python/fastapi_cadwyn_router/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/dag-runs/{run_id}/state", "GET", [Param.new("run_id", "", "path")]),
  Endpoint.new("/dags/{dag_id}", "GET", [Param.new("dag_id", "", "path")]),
  Endpoint.new("/execution/variables/{variable_key}", "GET", [Param.new("variable_key", "", "path")]),
]).perform_tests
