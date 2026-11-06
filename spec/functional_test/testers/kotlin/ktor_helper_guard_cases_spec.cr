require "../../func_spec.cr"

# Review cases for Ktor helper guards: only a helper that refuses a missing
# principal in an exact shape, called as a statement of the handler, from
# the helper's own Gradle module, guards it.
private def ktor_helper_case(name : String) : Hash(String, Bool)
  CodeLocator.instance.clear_all
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/ktor_helper_guard_cases/#{name}/")])
  options["ai_context"] = YAML::Any.new(true)
  options["nolog"] = YAML::Any.new(true)

  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints.to_h do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.ai_context.try { |context| !context.guards.empty? } || false}
  end
end

describe "Ktor helper guard cases", tags: "functional" do
  it "guards only a refusal of a missing principal" do
    ktor_helper_case("e").should eq({
      # Feature flag; the principal is only logged.
      "GET /feature" => false,
      # Guest-only: `p != null` and `principal()?.let { throw }`.
      "GET /guest"  => false,
      "GET /guest2" => false,
      # Rate limit keyed by user; anonymous allowed.
      "GET /rl" => false,
      # The guard call sits under an `if`.
      "GET /branch" => false,
      # The helper's name only appears in a string.
      "GET /str" => false,
      # The elvis on the line belongs to another expression.
      "GET /unrelated" => false,
      "GET /real"      => true,
    })
  end

  it "does not match a same-named function of another kind" do
    ktor_helper_case("f").should eq({"POST /orders" => false})
  end

  it "credits only a throwing, unconditional helper ahead of any answer" do
    ktor_helper_case("n").should eq({
      # The helper responds 401 but returns: the handler runs on.
      "POST /soft/{id}" => false,
      "POST /soft2"     => false,
      # `if (!Config.authEnabled) return` ahead of the refusal.
      "GET /setting" => false,
      "GET /rc"      => true,
      # A helper in a sibling module is not read (a missed guard, never an invented one).
      "GET /shared" => false,
      # An earlier `return@get call.respondText(...)` answers first.
      "GET /early"      => false,
      "GET /items/{id}" => true,
      "GET /real"       => true,
      # An earlier return with a project error status still refuses.
      "GET /archived" => true,
      "GET /data"     => false,
    })
  end

  it "reads only error statuses, from where the handler can see them" do
    ktor_helper_case("o").should eq({
      # A same-file constant that is a success status.
      "GET /okconst" => false,
      # A local `val STATUS = OK`; another package's `Codes.STATUS` is NotFound.
      "GET /collide"   => false,
      "GET /fromvalue" => false,
      "GET /notfound"  => true,
      "GET /var"       => false,
      # A `return@forEach` reads as an early return (a missed guard).
      "GET /foreach" => false,
    })
    ktor_helper_case("p").should eq({
      "GET /gone"   => true,
      "GET /denied" => true,
      "GET /okay"   => false,
      "GET /shadow" => false,
    })
  end

  it "resolves a helper in the handler's own Gradle module" do
    ktor_helper_case("m").should eq({
      "GET /admin/report" => true,
      "GET /shop/report"  => false,
    })
  end
end
