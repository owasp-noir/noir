require "../../func_spec.cr"

# The "large application" layout: each blueprint is declared in a
# package __init__.py and routed from a sibling views.py (`from . import
# auth`), and create_app() imports and registers it under another name
# (`auth as auth_blueprint`, `posts.bp`, `bp as users_bp`).
expected_endpoints = [
  Endpoint.new("/auth/login", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/own/", "GET"),
  Endpoint.new("/posts/<int:id>", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/", "GET"),
]

FunctionalTester.new("fixtures/python/flask_large_app/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
