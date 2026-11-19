require "../../func_spec.cr"

# `ViewSet.as_view({"get": "list", ...})` serves exactly the mapped verbs on
# its URL, each with the params of the action it names: inline, bound to a
# name in the urlconf, or bound in the views module. DRF's
# `obtain_auth_token` and simplejwt's token views serve POST only.
pk = Param.new("pk", "", "path")
title = Param.new("title", "", "form")
expected_endpoints = [
  Endpoint.new("/snippets/", "GET"),
  Endpoint.new("/snippets/", "POST", [title]),
  Endpoint.new("/snippets/<int:pk>/", "GET", [pk]),
  Endpoint.new("/snippets/<int:pk>/", "PUT", [pk]),
  Endpoint.new("/snippets/<int:pk>/", "PATCH", [pk]),
  Endpoint.new("/snippets/<int:pk>/", "DELETE", [pk]),
  Endpoint.new("/inline/", "GET"),
  Endpoint.new("/inline/", "POST", [title]),
  Endpoint.new("/inline/<int:pk>/", "GET", [pk]),
  Endpoint.new("/inline/<int:pk>/", "DELETE", [pk]),
  Endpoint.new("/api-token-auth/", "POST"),
  Endpoint.new("/api/token/", "POST"),
  Endpoint.new("/highlight/<int:pk>/", "POST", [pk]),
]

FunctionalTester.new("fixtures/python/django_drf_as_view_map/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
