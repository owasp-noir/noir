require "../../func_spec.cr"

# A wrapped HTTP client (`import api from './api'`) hides the raw axios
# instance behind a local module, so the axios import marker can't see
# it. The client-side UI framework import (pinia) is the signal that
# `web/store.js` is browser code: its `api.get(...)`/`api.post(...)`
# calls are outbound requests, not route registrations, and must be
# skipped. Only the real Express route survives.
expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_frontend_client_skip/", {
  :techs     => 1,
  :endpoints => 1,
}, expected_endpoints).perform_tests
