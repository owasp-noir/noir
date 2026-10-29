require "../../func_spec.cr"

# Regression (#3294): a Flask-WTF form created with no arguments binds the
# posted form data itself, directly (`LoginForm(FlaskForm)`) or through a
# project base (`ProfileForm(BaseForm)`, whose fields it inherits). A plain
# `wtforms.Form()` does not, nor one handed its source (`formdata=None`,
# `request.args`).
expected_endpoints = [
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("submit", "", "form"),
  ]),
  Endpoint.new("/profile", "POST", [Param.new("bio", "", "form"), Param.new("locale", "", "form")]),
  Endpoint.new("/plain", "POST"),
  Endpoint.new("/unbound", "POST"),
  Endpoint.new("/search", "POST"),
]

FunctionalTester.new("fixtures/python/flask_wtf_forms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Flask-WTF form negatives", tags: "functional" do
  it "does not bind a plain wtforms Form or a form handed its source" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_wtf_forms/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    %w[/plain /unbound /search].each do |url|
      app.endpoints.find! { |ep| ep.method == "POST" && ep.url == url }.params.should be_empty
    end
  end
end
