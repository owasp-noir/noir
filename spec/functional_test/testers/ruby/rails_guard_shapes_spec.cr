require "../../func_spec.cr"

# Rails guard shapes from Discourse and Mastodon (#3300), one app per
# subdirectory: what `noir query --guard` reports for each route.
private def rails_guard_report(name : String) : Hash(String, Endpoint)
  CodeLocator.instance.clear_all
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/ruby/rails_guard_shapes/#{name}/")])
  options["ai_context"] = YAML::Any.new(true)
  options["nolog"] = YAML::Any.new(true)
  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep} }
ensure
  CodeLocator.instance.clear_all
end

private def guard_tags(ep : Endpoint) : Array(String)
  ep.tags.select(&.name.in?("auth", "authz")).map { |tag| "#{tag.name}: #{tag.description}" }
end

describe "Rails guard shapes", tags: "functional" do
  it "does not trust `before_action :authorize_*` whose only raise refuses a credential that was sent" do
    report = rails_guard_report("authorize_prefix")
    guard_tags(report["PATCH /posts/:id"]).should be_empty
    guard_tags(report["DELETE /posts/:id"]).should be_empty
    # A callback of that name that refuses is still a guard.
    guard_tags(report["GET /reports"]).should eq([
      "auth: Protected by authorize_admin (app-defined, refuses callers without a credential)",
      "authz: Protected by authorize",
    ])
  end

  it "reads a callback that denies with `raise`, and a role check as authorization" do
    report = rails_guard_report("raise_deny")
    guard_tags(report["DELETE /drafts/:id"]).should eq(["auth: Protected by ensure_logged_in (app-defined, refuses callers without a credential)"])
    guard_tags(report["DELETE /admin/backups/:id"]).should eq([
      "auth: Protected by ensure_admin (app-defined, refuses callers without a credential)",
      "authz: Protected by ensure_admin (app-defined, refuses callers without admin?)",
    ])
  end

  it "follows a `requires_login` class setting a global callback reads" do
    report = rails_guard_report("requires_login_setting")
    guard_tags(report["DELETE /drafts/:id"]).should eq(["auth: Protected by block_if_requires_login (app-defined, refuses callers without a credential)"])
    guard_tags(report["GET /posts/:id"]).should be_empty
  end

  it "expands a `requires_login` macro that registers a before_action, with its options" do
    report = rails_guard_report("requires_login_macro")
    guard_tags(report["DELETE /drafts/:id"]).should eq(["auth: Protected by ensure_logged_in (app-defined, refuses callers without a credential)"])
    guard_tags(report["GET /drafts"]).should be_empty
    guard_tags(report["GET /posts/:id"]).should be_empty
  end

  it "resolves Pundit `alias` queries and `authorize [:ns, :record]`" do
    report = rails_guard_report("pundit_alias_array")
    guard_tags(report["POST /admin/subscriptions/purge"]).should eq(["authz: Protected by Pundit authorize"])
    guard_tags(report["POST /admin/subscriptions/review"]).should eq(["authz: Protected by Pundit authorize"])
  end

  it "finds an action defined in an included `lib/` module, with its params and the controller's guard" do
    report = rails_guard_report("lib_module_action")
    multipart = report["POST /uploads/create-multipart"]
    handler = multipart.handler.should_not be_nil
    handler.path.to_s.should end_with("lib/external_upload_helpers.rb")
    handler.line.should eq(4)
    multipart.params.map(&.name).should eq(["file_name"])
    guard_tags(multipart).should eq(["auth: Protected by Devise authenticate_user!"])
  end
end
