require "../../func_spec.cr"

# #3272: body containers and request-field aliases land in the right place.
describe "Python param attribution", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  params_for = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/#{fixture}/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints.to_h { |e| {"#{e.method} #{e.url}", e.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!} }
  end

  it "reads FastAPI dict/list params as body unless Query() says otherwise" do
    rows = params_for.call("fastapi_container_body")
    rows["POST /items"].should eq(["payload:json", "tags:json"])
    rows["GET /search"].should eq(["ids:query", "labels:query", "q:query"])
    rows["POST /bulk"].should eq(["names:json"])
    # The dependency's own params, not an `ids` body field.
    rows["GET /picked"].should eq(["raw:query"])
  end

  it "reads Flask fields through a request.form / request.args alias" do
    rows = params_for.call("flask_form_alias")
    rows["POST /users/action"].should eq(["first_name:form", "last_name:form"])
    rows["POST /users/direct"].should eq(["first_name:form"])
    rows["GET /search"].should eq(["page:query", "q:query", "sort:query"])
    # `name = request.form.get("name")` binds a value, not the form.
    rows["POST /single"].should eq(["name:form"])
    rows["POST /fallback"].should eq(["title:form"])
    # A `form=request.form` keyword argument binds no local.
    rows["POST /render"].should be_empty
  end
end
