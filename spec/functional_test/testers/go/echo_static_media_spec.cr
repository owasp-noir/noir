require "../../func_spec.cr"

# `e.Static("/static", "public")` serves every file in the directory,
# including the images, fonts and SVGs the media filter keeps out of the
# file index.
expected_endpoints = [
  Endpoint.new("/static/site.css", "GET"),
  Endpoint.new("/static/img/logo.svg", "GET"),
  Endpoint.new("/static/img/pic.png", "GET"),
  Endpoint.new("/static/font.woff2", "GET"),
  Endpoint.new("/static/font.woff2.1", "GET"),
  Endpoint.new("/static/favicon.ico", "GET"),
]

FunctionalTester.new("fixtures/go/echo_static_media/", {
  :techs => 1,
}, expected_endpoints).perform_tests
