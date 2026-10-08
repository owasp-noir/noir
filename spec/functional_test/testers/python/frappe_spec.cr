require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/method/library_app.api.get_books", "GET", [
    Param.new("category", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/method/library_app.api.get_books", "POST", [
    Param.new("category", "", "form"),
    Param.new("limit", "", "form"),
  ]),
  Endpoint.new("/api/method/library_app.api.issue_book", "POST", [
    Param.new("book", "", "form"),
    Param.new("member", "", "form"),
    Param.new("due_date", "", "form"),
  ]),
  Endpoint.new("/api/method/library_app.api.search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/method/library_app.api.stats", "GET", [
    Param.new("member", "", "query"),
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/api/method/library_app.api.stats", "POST", [
    Param.new("member", "", "form"),
    Param.new("status", "", "form"),
  ]),
  Endpoint.new("/api/method/library_app.library.doctype.book.book.get_availability", "GET", [
    Param.new("book", "", "query"),
  ]),
  Endpoint.new("/api/method/library_app.library.doctype.book.book.get_availability", "POST", [
    Param.new("book", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/python/frappe/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Frappe whitelist flags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags allow_guest and xss_safe from @frappe.whitelist" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/frappe/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    tags = ->(method : String, url : String) do
      app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.map(&.name)
    end

    tags.call("GET", "/api/method/library_app.api.get_books").should eq ["frappe-allow-guest"]
    tags.call("GET", "/api/method/library_app.api.search").should eq ["frappe-allow-guest", "frappe-xss-safe"]
    tags.call("POST", "/api/method/library_app.api.issue_book").should eq ["auth"]
  end
end
