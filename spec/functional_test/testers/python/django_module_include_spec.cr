require "../../func_spec.cr"

# `include(shop.urls)` after `import shop.urls` mounts the shop urlconf
# under /shop/; it used to be mistaken for a DRF router's url list, losing
# the prefix and adding a phantom `GET /shop/`.
extracted_endpoints = [
  Endpoint.new("/shop/cart/", "GET"),
]

FunctionalTester.new("fixtures/python/django_module_include/", {
  :techs     => 1,
  :endpoints => 1,
}, extracted_endpoints).perform_tests
