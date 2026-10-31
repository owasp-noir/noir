require "../../func_spec.cr"

describe "--ai-context on FastAPI dependency instances", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "judges an Authenticator instance by its class's __call__ and the instance's arguments" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/fastapi_authenticator_instance/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guards = app.endpoints.to_h do |ep|
      {ep.url, ep.ai_context.try(&.guards.select(&.kind.==("auth_guard")).map(&.name)) || [] of String}
    end

    # `auth.ItemsRead` (a module-qualified alias written over three lines)
    # over `Authenticator(allowed_subjects={User})`, whose `__call__` raises
    # Unauthorized for an anonymous subject.
    guards["/items/"].should eq(["FastAPI Depends(_ItemsRead) (ItemsRead)"])
    # Through an alias whose dependency is typed with another alias, a
    # factory's nested dependency, a local instance in a factory, and an
    # instance built inline in the handler signature.
    guards["/items/mine"].should eq(["FastAPI Depends(ScopeAuthorizer) (AuthorizeRead)"])
    guards["/items/org/{org_id}"].should eq(["FastAPI Depends(OrgGuard) (OrgAccess)"])
    guards["/items/scopes"].should eq(["FastAPI Depends(Authenticator(...))"])
    # The instance lets an anonymous subject in: `Anonymous in
    # self.allowed_subjects` returns before the raise.
    guards["/items/browse"].should be_empty
    guards["/items/maybe"].should be_empty
    # The instance's arguments, however they are passed: positionally,
    # through a module constant, or forwarded by a factory's parameter.
    guards["/flags/positional"].should be_empty
    guards["/flags/constant"].should be_empty
    guards["/flags/forwarded"].should be_empty
    guards["/flags/forwarded-default"].should eq(["FastAPI Depends(Guard(...))"])
    # `if self.auto_error: raise`: `auto_error=False` refuses nobody.
    guards["/flags/optional-token"].should be_empty
    guards["/flags/maybe-token"].should be_empty
    guards["/flags/required-token"].should eq(["FastAPI Depends(required_token)"])
    # A 403 that does not turn on a missing caller (a rate limit, a check on
    # a caller who is there) is no authentication guard.
    guards["/flags/limited"].should be_empty
    guards["/flags/banned"].should be_empty
    # `ItemsRead` imported from a module outside the scan is not the
    # project's `ItemsRead` alias.
    guards["/flags/foreign"].should be_empty
    # The same gate spelled `not in ... raise`.
    guards["/items/strict"].should eq(["FastAPI Depends(strict)"])
    guards["/items/lenient"].should be_empty
    guards["/items/open"].should be_empty
  end
end
