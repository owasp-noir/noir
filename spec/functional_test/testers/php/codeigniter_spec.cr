require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/users/{num}", "GET", [Param.new("num", "", "path")]),
  Endpoint.new("/users/{num}", "PUT", [Param.new("num", "", "path")]),
  Endpoint.new("/users/{num}", "DELETE", [Param.new("num", "", "path")]),
  Endpoint.new("/contact", "GET"),
  Endpoint.new("/contact", "POST"),
  Endpoint.new("/webhook", "GET"),
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/webhook", "PUT"),
  Endpoint.new("/webhook", "PATCH"),
  Endpoint.new("/webhook", "DELETE"),
  Endpoint.new("/photos", "GET"),
  Endpoint.new("/photos", "POST"),
  Endpoint.new("/photos/new", "GET"),
  Endpoint.new("/photos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/{id}/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/photos/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/articles", "GET"),
  Endpoint.new("/articles/show/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/new", "GET"),
  Endpoint.new("/articles/create", "POST"),
  Endpoint.new("/articles/edit/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/update/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/remove/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/delete/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/debug", "GET"),
]

FunctionalTester.new("fixtures/php/codeigniter/", {
  :techs     => 2,  # php_codeigniter + php_pure
  :endpoints => 38, # 36 CodeIgniter routes + 2 php_pure files (Routes.php, Home.php)
}, expected_endpoints).perform_tests
