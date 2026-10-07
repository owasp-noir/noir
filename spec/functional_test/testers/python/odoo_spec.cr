require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/shop/cart", "GET", [
    Param.new("access_token", "", "query"),
    Param.new("coupon", "", "query"),
  ]),
  Endpoint.new("/shop/cart", "POST", [
    Param.new("access_token", "", "form"),
    Param.new("coupon", "", "form"),
  ]),
  Endpoint.new("/shop", "GET", [
    Param.new("page", "", "query"),
    Param.new("category", "", "query"),
    Param.new("search", "", "query"),
  ]),
  Endpoint.new("/shop", "POST", [
    Param.new("page", "", "form"),
    Param.new("category", "", "form"),
    Param.new("search", "", "form"),
  ]),
  Endpoint.new("/shop/page/{page}", "GET", [
    Param.new("page", "", "path"),
    Param.new("category", "", "query"),
    Param.new("search", "", "query"),
  ]),
  Endpoint.new("/shop/page/{page}", "POST", [
    Param.new("page", "", "path"),
    Param.new("category", "", "form"),
    Param.new("search", "", "form"),
  ]),
  Endpoint.new("/shop/category/{category}", "GET", [
    Param.new("category", "", "path"),
    Param.new("page", "", "query"),
    Param.new("search", "", "query"),
  ]),
  Endpoint.new("/shop/category/{category}", "POST", [
    Param.new("category", "", "path"),
    Param.new("page", "", "form"),
    Param.new("search", "", "form"),
  ]),
  Endpoint.new("/shop/cart/update_json", "POST", [
    Param.new("product_id", "", "json"),
    Param.new("add_qty", "", "json"),
  ]),
  Endpoint.new("/my/orders/{order_id}/cancel", "POST", [
    Param.new("order_id", "", "path"),
    Param.new("reason", "", "form"),
    Param.new("note", "", "form"),
  ]),
  Endpoint.new("/shop/payment/validate", "POST", [
    Param.new("transaction_id", "", "json"),
  ]),
  Endpoint.new("/shop/address", "GET", [
    Param.new("partner_id", "", "query"),
  ]),
  Endpoint.new("/shop/address", "POST", [
    Param.new("partner_id", "", "form"),
  ]),
  Endpoint.new("/shop/address/submit", "POST", [
    Param.new("partner_id", "", "json"),
  ]),
  Endpoint.new("/xmlrpc/2/{service}", "POST", [
    Param.new("service", "", "path"),
  ]),
  Endpoint.new("/xmlrpc/{service}", "POST", [
    Param.new("service", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/python/odoo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Odoo route flags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags auth, type and csrf from @http.route" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/odoo/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map { |tag| {tag.name, tag.description} }
    end

    cart = tags.call("GET", "/shop/cart")
    cart.should contain({"odoo-auth", "public"})
    cart.should contain({"odoo-type", "http"})
    cart.should contain({"csrf-disabled", "Odoo csrf=False"})
    cart.map(&.first).should_not contain("auth")

    cancel = tags.call("POST", "/my/orders/{order_id}/cancel")
    cancel.should contain({"auth", "Protected by Odoo auth='user'"})
    cancel.map(&.first).should_not contain("csrf-disabled")

    tags.call("POST", "/shop/payment/validate").should contain({"odoo-type", "jsonrpc"})
    tags.call("POST", "/xmlrpc/{service}").should contain({"odoo-auth", "none"})
  end
end
