require "../func_spec.cr"

extected_endpoints = [
  # djangoproject/urls/www.py
  Endpoint.new("/start/overview/", "GET"),
  Endpoint.new("/overview/", "GET"),
  # accounts/urls.py
  Endpoint.new("/accounts/register/", "GET"),
  Endpoint.new("/accounts/edit/", "GET"),
  Endpoint.new("/accounts/", "GET"),
]

FunctionalTester.new("fixtures/django/", {
  :techs     => 1,
  :endpoints => 5,
}, extected_endpoints).test_all
