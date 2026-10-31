require "../../func_spec.cr"

# `use App\Http\Requests\ItemRequest as Request;` is an app FormRequest named
# `Request`: its rules() keys are the action's params. The framework's own
# `Request` and an aliased class that is no FormRequest contribute none.
expected_endpoints = [
  Endpoint.new("/items", "POST", [
    Param.new("name", "", "form"),
    Param.new("sale_price", "", "form"),
  ]),
  Endpoint.new("/plain", "POST"),
  Endpoint.new("/framework", "POST", [Param.new("plain", "", "form")]),
]

FunctionalTester.new("fixtures/php/laravel_aliased_request/", {
  :techs     => 2,
  :endpoints => 3,
}, expected_endpoints).perform_tests
