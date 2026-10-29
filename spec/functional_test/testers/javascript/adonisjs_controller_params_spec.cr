require "../../func_spec.cr"

# #3309: params come from the controller action a route names
# (`[NotesController, 'store']` behind a lazy `import()`).
expected_endpoints = [
  Endpoint.new("/api/notes", "POST", [Param.new("title", "", "json"), Param.new("body", "", "json")]),
  Endpoint.new("/api/notes/search", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/notes/:id", "DELETE", [Param.new("id", "", "path")]),
  # Inline `[() => import('#controllers/...'), 'store']`, same action body.
  Endpoint.new("/notes/inline", "PUT", [Param.new("title", "", "json"), Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/javascript/adonisjs_controller_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
