require "../../func_spec.cr"

describe "--ai-context on flask-allows requirements", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads allows.requires / requires as an authorization check" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_allows/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guards = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.guards.map { |g| "#{g.kind}:#{g.name}" }) || [] of String}
    end

    # FlaskBB's MethodView `decorators = [allows.requires(IsAdmin, ...)]` on
    # the `Allows(...)` instance, and a bare `@requires(...)` imported from
    # flask_allows.
    guards["GET /admin/settings"].should eq(["authz_guard:flask-allows requires"])
    guards["POST /admin/settings"].should eq(["authz_guard:flask-allows requires"])
    guards["POST /admin/purge"].should eq(["authz_guard:flask-allows requires"])
    # A requirement built per request from the resource (FlaskBB's
    # `ForRequest(can_access_forum, request_forum)`) is still the check,
    # and says the resource's settings can admit a guest.
    guards["GET /board"].should eq(["authz_guard:flask-allows requires (a per-request requirement: the resource's settings can admit a guest)"])
    # A class without decorators, a requirement that only negates, and a
    # project's own `allows = Allows()` (its module merely mentions
    # flask_allows in a docstring) guard nothing.
    # Bound by the imports: a parenthesised multi-line import, an alias
    # (`requires as perm_req`, `Allows as Perms`), the module itself
    # (`import flask_allows as fa`); `Not` negates only its own argument.
    %w[/aliased /module /perms /both /not-banned-admin].each do |url|
      guards["GET #{url}"].should eq(["authz_guard:flask-allows requires"])
    end
    # A project's own `requires` imported over the name checks nothing.
    guards["GET /scoped"].should be_empty
    guards["GET /overview"].should be_empty
    guards["GET /guests-only"].should be_empty
    guards["GET /bucketed"].should be_empty
  end
end
