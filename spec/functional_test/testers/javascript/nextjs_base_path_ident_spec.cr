require "../../func_spec.cr"

# `basePath` given through an identifier (`{ basePath }`, `basePath: BASE`)
# resolves only to a string literal declared in the same config. An env
# lookup, a template, a commented-out key or another property reading the
# same constant (`assetPrefix: basePath`) leaves the routes unprefixed.
expected_endpoints = [] of Endpoint
%w[/portal/api/hello /esm/api/status /api/env /api/tpl /api/commented /api/prefix].each do |url|
  %w[GET POST PUT DELETE PATCH].each { |method| expected_endpoints << Endpoint.new(url, method) }
end

FunctionalTester.new("fixtures/javascript/nextjs_base_path_ident/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
