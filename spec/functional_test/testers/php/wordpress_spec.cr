require "../../func_spec.cr"

expected_endpoints = [
  # REST API (register_rest_route -> /wp-json/{namespace}/{route})
  Endpoint.new("/wp-json/myplugin/v1/books", "GET"),
  Endpoint.new("/wp-json/myplugin/v1/books/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v1/books/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v1/books/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v1/books/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v2/authors", "GET"),
  Endpoint.new("/wp-json/myplugin/v2/authors", "POST"),
  Endpoint.new("/wp-json/store/v1/checkout", "POST"),
  # Nested-group named param normalizes cleanly (no stray ')').
  Endpoint.new("/wp-json/myplugin/v1/items/{type}", "GET", [Param.new("type", "", "path")]),
  # Optional non-capturing segment: (?:...) and trailing ? stripped.
  Endpoint.new("/wp-json/myplugin/v1/optional/{id}", "GET", [Param.new("id", "", "path")]),
  # Commented-out 'methods' => 'DELETE' must not emit a phantom verb.
  Endpoint.new("/wp-json/myplugin/v1/comments", "GET"),

  # admin-ajax.php actions (wp_ajax_ / wp_ajax_nopriv_)
  Endpoint.new("/wp-admin/admin-ajax.php?action=get_user_data", "GET", [Param.new("action", "get_user_data", "query")]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=get_user_data", "POST", [Param.new("action", "get_user_data", "query")]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=save_settings", "GET", [Param.new("action", "save_settings", "query")]),
  Endpoint.new("/wp-admin/admin-ajax.php?action=save_settings", "POST", [Param.new("action", "save_settings", "query")]),

  # admin-post.php actions (admin_post_ / admin_post_nopriv_)
  Endpoint.new("/wp-admin/admin-post.php?action=export_csv", "GET", [Param.new("action", "export_csv", "query")]),
  Endpoint.new("/wp-admin/admin-post.php?action=export_csv", "POST", [Param.new("action", "export_csv", "query")]),
  Endpoint.new("/wp-admin/admin-post.php?action=public_submit", "GET", [Param.new("action", "public_submit", "query")]),
  Endpoint.new("/wp-admin/admin-post.php?action=public_submit", "POST", [Param.new("action", "public_submit", "query")]),
]

FunctionalTester.new("fixtures/php/wordpress/", {
  :techs     => 2, # php_wordpress + php_pure (suppressed in analysis)
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
