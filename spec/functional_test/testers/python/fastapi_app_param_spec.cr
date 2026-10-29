require "../../func_spec.cr"

# Airflow's `init_views(app: FastAPI)`: the app is built in `main.py` and
# handed to a function that includes the routers and declares routes on
# it. The annotated parameter is a mount root like `app = FastAPI()`.
FunctionalTester.new("fixtures/python/fastapi_app_param/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/api/v2/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/health", "GET"),
]).perform_tests
