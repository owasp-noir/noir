require "../../func_spec.cr"

# A plain PHP site serves its root `docs/` section like any other directory:
# `docs/index.php?page=…` and `docs/search.php` are pages, not runnable
# documentation snippets.
expected_endpoints = [
  Endpoint.new("/index.php", "GET", [
    Param.new("home", "", "query"),
  ]),
  Endpoint.new("/docs/index.php", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/docs/search.php", "GET", [
    Param.new("term", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/php/pure_docs_section/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests
