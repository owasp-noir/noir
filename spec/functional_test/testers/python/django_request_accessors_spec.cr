require "../../func_spec.cr"

# `request.headers` and `request.FILES` are request inputs, and a
# `request.META` key is reported as the header the client sends
# (`HTTP_X_FORWARDED_FOR` -> `x-forwarded-for`); REMOTE_ADDR is server
# state, not a header.
extracted_endpoints = [
  Endpoint.new("/headers/", "GET", [
    Param.new("X-Api-Token", "", "header"),
    Param.new("x-forwarded-for", "", "header"),
    Param.new("content-type", "", "header"),
  ]),
  Endpoint.new("/upload/", "GET"),
  Endpoint.new("/upload/", "POST", [Param.new("document", "", "form")]),
]

FunctionalTester.new("fixtures/python/django_request_accessors/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
