require "../../func_spec.cr"

# Remix flat-file escapes: `jokes[.]rss` -> `/jokes.rss` (the bracketed `.`
# is a literal, not a separator) and `$contactId_` -> `{contactId}` (the
# trailing `_` is the layout opt-out marker, stripped from the URL/param).
expected_endpoints = [
  Endpoint.new("/jokes.rss", "GET"),
  Endpoint.new("/contacts/{contactId}/edit", "GET", [Param.new("contactId", "", "path")]),
  Endpoint.new("/contacts/{contactId}/edit", "POST", [Param.new("contactId", "", "path")]),
  Endpoint.new("/contacts/{contactId}/edit", "PUT", [Param.new("contactId", "", "path")]),
  Endpoint.new("/contacts/{contactId}/edit", "PATCH", [Param.new("contactId", "", "path")]),
  Endpoint.new("/contacts/{contactId}/edit", "DELETE", [Param.new("contactId", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/remix_escape_segments/", {
  :techs => 1,
}, expected_endpoints).perform_tests
