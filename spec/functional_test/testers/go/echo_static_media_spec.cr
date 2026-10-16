require "../../func_spec.cr"

# `e.Static("/static", "public")` serves every file in the directory,
# including the images, fonts and SVGs the media filter keeps out of the
# file index. `root_mount/` serves its own directory (`e.Static("/", ".")`):
# the walk's pruned subtrees (`node_modules/`) are not served files.
expected_endpoints = [
  Endpoint.new("/static/site.css", "GET"),
  Endpoint.new("/static/img/logo.svg", "GET"),
  Endpoint.new("/static/img/pic.png", "GET"),
  Endpoint.new("/static/font.woff2", "GET"),
  Endpoint.new("/static/font.woff2.1", "GET"),
  Endpoint.new("/static/favicon.ico", "GET"),
  Endpoint.new("/server.go", "GET"),
  Endpoint.new("/assets/mark.svg", "GET"),
]

# The count pins `root_mount/node_modules/` (pruned by the walk) as absent.
FunctionalTester.new("fixtures/go/echo_static_media/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
