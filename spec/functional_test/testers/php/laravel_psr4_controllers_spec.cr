require "../../func_spec.cr"

# Controllers outside `app/` are found through PSR-4: a module's own
# `composer.json` (`Modules\Shop\` => `app/`) and the root one
# (`Acme\Billing\` => `packages/acme/billing/src/`).
expected_endpoints = [
  Endpoint.new("/control", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/shop", "GET", [Param.new("category", "", "query")]),
  Endpoint.new("/shop/orders", "POST", [Param.new("sku", "", "form"), Param.new("qty", "", "form")]),
  Endpoint.new("/billing/invoices", "POST", [Param.new("amount", "", "form")]),
]

tester = FunctionalTester.new("fixtures/php/laravel_psr4_controllers/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Laravel PSR-4 controllers", tags: "functional" do
  it "names the module and package handlers" do
    handler = ->(url : String) { tester.app.endpoints.find! { |ep| ep.url == url }.handler.try(&.name) }

    handler.call("/shop").should eq("ShopController@index")
    handler.call("/shop/orders").should eq("ShopController@store")
    handler.call("/billing/invoices").should eq("InvoiceController@store")
  end
end
