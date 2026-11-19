require "../../func_spec.cr"

# Params read by the callback: `get_param`, `$request['x']`, `get_header`
# and `get_file_params()` for REST; superglobals, `filter_input` and the
# `check_ajax_referer` nonce field for admin-ajax / admin-post hooks.
expected_endpoints = [
  Endpoint.new("/wp-json/myplugin/v1/control/{id}", "GET", [Param.new("id", "", "path"), Param.new("declared", "", "query")]),
  Endpoint.new("/wp-json/myplugin/v1/orders", "POST", [
    Param.new("sku", "", "form"),
    Param.new("qty", "", "form"),
    Param.new("X-Shop-Token", "", "header"),
    Param.new("receipt", "", "file"),
  ]),
  Endpoint.new("/wp-json/myplugin/v1/search", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_save", "GET", [
    Param.new("action", "myplugin_save", "query"), Param.new("title", "", "form"), Param.new("nonce", "", "query"),
  ]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_save", "POST", [
    Param.new("action", "myplugin_save", "query"), Param.new("title", "", "form"), Param.new("nonce", "", "form"),
  ]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_lookup", "GET", [
    Param.new("action", "myplugin_lookup", "query"), Param.new("term", "", "query"), Param.new("post_id", "", "query"),
  ]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_lookup", "POST", [
    Param.new("action", "myplugin_lookup", "query"), Param.new("term", "", "query"), Param.new("post_id", "", "form"),
  ]),
  Endpoint.new("/wp-admin/admin-post.php?action=myplugin_export", "GET", [
    Param.new("action", "myplugin_export", "query"), Param.new("format", "", "query"), Param.new("theme", "", "cookie"),
  ]),
  Endpoint.new("/wp-admin/admin-post.php?action=myplugin_export", "POST", [
    Param.new("action", "myplugin_export", "query"), Param.new("format", "", "query"), Param.new("theme", "", "cookie"),
  ]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_upload", "GET", [
    Param.new("action", "myplugin_upload", "query"), Param.new("attachment", "", "file"), Param.new("USER-AGENT", "", "header"),
  ]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=myplugin_upload", "POST", [
    Param.new("action", "myplugin_upload", "query"), Param.new("attachment", "", "file"), Param.new("USER-AGENT", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/php/wordpress_callback_params/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
