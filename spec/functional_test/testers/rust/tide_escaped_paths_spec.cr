require "../../func_spec.cr"

# A route path containing a Rust string escape must survive intact.
#
# tree-sitter-rust splits a string literal at every escape, so
# `"/page-{id:\d+}"` parses as string_content `/page-{id:`, escape_sequence
# `\d`, string_content `+}`. Eight of the ten Rust adapters read only the
# first `string_content` child, which truncated the path to `/page-{id:` —
# a URL that matches nothing, with the param lost.
#
# Regex-constrained path params are ordinary in tide, actix and rocket, so
# this is not an exotic shape. No pre-existing Rust fixture carried one,
# which is exactly why the truncation survived: the whole fixture sweep
# compared clean either way.
expected_endpoints = [
  Endpoint.new("/page-{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/file-{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/plain/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/tide_escaped_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
