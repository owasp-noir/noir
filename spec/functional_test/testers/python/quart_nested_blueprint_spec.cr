require "../../func_spec.cr"

# A blueprint registered on a blueprint declared in another file is served
# under the parent's prefixes (#3593), the same way Flask resolves it.
expected_endpoints = [
  Endpoint.new("/chatbot/health", "GET"),
  # chat_bp (own /genai) on root_bp (/chatbot), across files.
  Endpoint.new("/chatbot/genai/ask", "POST"),
  # url_prefix at the nested registration replaces admin_bp's own /admin.
  Endpoint.new("/chatbot/manage/users", "GET"),
  # Two levels: leaf_bp on mid_bp on root_bp.
  Endpoint.new("/chatbot/mid/ping", "GET"),
  Endpoint.new("/chatbot/mid/leaf/item", "GET"),
  # One child under two parents.
  Endpoint.new("/chatbot/shared/status", "GET"),
  Endpoint.new("/other/shared/status", "GET"),
  # Never registered: its own prefix only.
  Endpoint.new("/orphan/lonely", "GET"),
]

# cycle_a/cycle_b register each other: the bounded passes must terminate.
# Their two routes are counted, but their URLs are not asserted.
FunctionalTester.new("fixtures/python/quart_nested_blueprint/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size + 2,
}, expected_endpoints).perform_tests
