require "../../func_spec.cr"

# Request inputs read through one indirection, each judged by its
# definition: a form class a setting names (`import_string(settings.X)`
# through a project loader), the serializer a generic view's `create`
# validates, a DRF DELETE's own `request.data` read (not one under another
# verb's `request.method` branch), and a project helper handed
# `request.GET` and a key it looks up.
expected_endpoints = [
  Endpoint.new("/login/", "GET"),
  Endpoint.new("/login/", "POST", [Param.new("email", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/validate/", "POST", [Param.new("label_config", "", "form")]),
  Endpoint.new("/versions/<int:pk>/", "GET", [Param.new("pk", "", "path"), Param.new("verbose", "", "query")]),
  Endpoint.new("/versions/<int:pk>/", "DELETE", [Param.new("pk", "", "path"), Param.new("version", "", "form")]),
  Endpoint.new("/items/{pk}/", "DELETE", [Param.new("pk", "", "path"), Param.new("reason", "", "form")]),
  Endpoint.new("/items/{pk}/notes/", "DELETE", [Param.new("pk", "", "path"), Param.new("id", "", "query")]),
  Endpoint.new("/items/{pk}/notes/", "POST", [Param.new("pk", "", "path"), Param.new("note", "", "form")]),
]

FunctionalTester.new("fixtures/python/django_request_inputs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Django indirect request inputs", tags: "functional" do
  it "drops computed cleaned_data keys and another verb's body reads" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/django_request_inputs/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/login/" }
    post.params.map(&.name).should_not contain("user")
    delete = app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/items/{pk}/notes/" }
    delete.params.map(&.name).should_not contain("note")
  end
end
