require "../../func_spec.cr"

expected_endpoints = [
  # From routes/web.php - basic routes
  Endpoint.new("/", "GET"),
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),

  # From Route::resource('products', ProductController::class)
  Endpoint.new("/products", "GET"),
  Endpoint.new("/products/create", "GET"),
  Endpoint.new("/products", "POST"),
  Endpoint.new("/products/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/products/{id}/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/products/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/products/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/products/{id}", "DELETE", [Param.new("id", "", "path")]),

  # From Route::match
  Endpoint.new("/contact", "GET"),
  Endpoint.new("/contact", "POST"),

  # From Route::any
  Endpoint.new("/webhook", "GET"),
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/webhook", "PUT"),
  Endpoint.new("/webhook", "PATCH"),
  Endpoint.new("/webhook", "DELETE"),
  Endpoint.new("/webhook", "OPTIONS"),
  Endpoint.new("/webhook", "HEAD"),

  # From routes/api.php - basic routes
  Endpoint.new("/health", "GET"),

  # From Route::apiResource('users', ApiUserController::class)
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),

  # From Route::apiResource('posts', PostController::class)
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/{id}", "DELETE", [Param.new("id", "", "path")]),

  # Individual routes from api.php
  Endpoint.new("/categories", "GET"),
  Endpoint.new("/categories", "POST"),
  Endpoint.new("/categories/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/status/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/cors-test", "OPTIONS"),

  # From php_pure detector (PHP files in controllers) - these are detected by php_pure analyzer
  Endpoint.new("/app/Http/Controllers/UserController.php", "GET"),
  Endpoint.new("/app/Http/Controllers/ProductController.php", "GET"),
]

FunctionalTester.new("fixtures/php/laravel/", {
  :techs     => 2,  # Both php_laravel and php_pure are detected
  :endpoints => 51, # Actual detected endpoint count
}, expected_endpoints).perform_tests