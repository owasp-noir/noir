require "../../func_spec.cr"

def grails_endpoint_with_callees(url, method, callees = [] of Callee)
  endpoint = Endpoint.new(url, method)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

index_callees = [
  Callee.new("bookService.list", line: 17),
  Callee.new("AuditLog.write", line: 18),
  Callee.new("render", line: 20),
]

save_callees = [
  Callee.new("bookService.save", line: 24),
  Callee.new("respond", line: 25),
]

update_callees = [
  Callee.new("bookService.update", line: 29),
  Callee.new("withTransaction", line: 30),
  Callee.new("AuditLog.write", line: 31),
  Callee.new("redirect", line: 33),
]

show_callees = [
  Callee.new("render", line: 40),
  Callee.new("bookService.find", line: 40),
]

list_callees = [
  Callee.new("authorService.list", line: 7),
  Callee.new("render", line: 8),
]

profile_callees = [
  Callee.new("profileService.show", line: 12),
  Callee.new("render", line: 13),
]

expected_endpoints = [
  grails_endpoint_with_callees("/book/index", "GET", index_callees),
  grails_endpoint_with_callees("/book/save", "POST", save_callees),
  grails_endpoint_with_callees("/book/update", "PUT", update_callees),
  grails_endpoint_with_callees("/book/update", "PATCH", update_callees),
  grails_endpoint_with_callees("/book/show", "GET", show_callees),
  grails_endpoint_with_callees("/author/list", "GET", list_callees),
  grails_endpoint_with_callees("/author/profile", "GET", profile_callees),
  Endpoint.new("/product/index", "GET"),
  Endpoint.new("/product/show", "GET"),
  Endpoint.new("/product/create", "GET"),
  Endpoint.new("/product/save", "POST"),
  Endpoint.new("/product/edit", "GET"),
  Endpoint.new("/product/update", "PUT"),
  Endpoint.new("/product/delete", "DELETE"),
]

tester = FunctionalTester.new("fixtures/groovy/grails_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Grails callees for allowedMethods fan-out" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/book/update" && found.method == "PUT" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(update_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "handles Groovy literals and safe navigation in Grails action bodies" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/book/show" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(show_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "does not attach callees to scaffold-generated Grails actions" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/product/save" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.should be_empty
  end
end

it "populates Grails callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/book/index" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/groovy/grails_callees/grails-app/controllers/BookController.groovy",
    ])
  end
end
