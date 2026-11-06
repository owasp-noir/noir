require "../../func_spec.cr"

# A hook that refuses the routes whose own `config` sets a key
# (`req.routeOptions.config?.permissions`) guards exactly those routes.
describe "Fastify hooks gated on route config", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards the routes that set the key the hook refuses on" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/fastify_config_gate/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    guards_of = ->(url : String) do
      app.endpoints.find! { |e| e.url == url }.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("/api/admin").join(" ").should contain("config.permissions")
    guards_of.call("/api/none").should be_empty
    guards_of.call("/api/public").should be_empty
    # A hook that refuses routes lacking the key opens the ones that set it.
    guards_of.call("/inverse/anon").should be_empty
    guards_of.call("/api/plain").should be_empty
    # The same hook still refuses the routes that do not set the key.
    guards_of.call("/inverse/plain").join(" ").should contain("onRequest")
    # A negated group tests the key's absence too.
    guards_of.call("/inverse/roles").should be_empty
    guards_of.call("/inverse/noroles").join(" ").should contain("preHandler")
    # `typeof x === 'undefined'` and `Array.isArray(x) === false` test absence.
    guards_of.call("/inverse/tier").should be_empty
    # An encapsulated plugin's gate does not reach another plugin's routes.
    guards_of.call("/pg/inside").join(" ").should contain("config.level")
    guards_of.call("/pr/elsewhere").should be_empty
    # A comment naming Fastify() or an unrelated fp() does not make a file the root.
    guards_of.call("/lk/own").join(" ").should contain("config.tier")
    guards_of.call("/pr/sibling").should be_empty
    # A gate inside a fastify-plugin reaches its siblings.
    guards_of.call("/pr/vip").join(" ").should contain("config.vip")
    # A hook inside a register callback guards only that callback's routes.
    guards_of.call("/scoped/inside").join(" ").should contain("config.role")
    guards_of.call("/scoped/outside").should be_empty
  end
end
