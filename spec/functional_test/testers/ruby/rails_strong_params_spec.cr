require "../../func_spec.cr"

# Strong-params lists named indirectly: a local array built up with `<<`
# from a constant splat and a `{ tags: [] }` hash, Pundit's
# `permitted_attributes(Comment)` (the policy's
# `permitted_attributes_for_create`), the leaf of `params.dig(:page, :x)`,
# and a nested `resources ..., to: "ctrl#action"`. The local's name and the
# permit root (`article`, read whole by a guard line) are not fields.
# A permit list may also hang off a helper that returns
# `params.require(key)` (`params_for(:item).permit(...)`) or off a
# local bound to `params.require(:order)` / `params[:note]`; the container
# key is not a field then either, by the same rule as a permit root, even
# if the local is also passed whole somewhere. A Devise sessions override that never
# calls `super` reads none of Devise's sign-in params; a passwords override
# that calls `super`, or a helper reading `resource_params`, keeps them.
article_fields = [
  Param.new("id", "", "path"),
  Param.new("title", "", "form"),
  Param.new("body", "", "form"),
  Param.new("tags", "", "form"),
  Param.new("pinned", "", "form"),
]

expected_endpoints = [
  Endpoint.new("/articles/:id", "PUT", article_fields),
  Endpoint.new("/articles/:id", "PATCH", article_fields),
  Endpoint.new("/comments", "POST", [
    Param.new("body", "", "form"),
    Param.new("parent_id", "", "form"),
  ]),
  Endpoint.new("/books", "POST", [
    Param.new("title", "", "form"),
    Param.new("author", "", "form"),
  ]),
  Endpoint.new("/books/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("book", "", "form"),
  ]),
  Endpoint.new("/pages/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("slug_suffix", "", "form"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
  ]),
  Endpoint.new("/items/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
  ]),
  Endpoint.new("/orders", "POST", [
    Param.new("quantity", "", "form"),
    Param.new("note", "", "form"),
  ]),
  Endpoint.new("/notes", "POST", [
    Param.new("text", "", "form"),
    Param.new("color", "", "form"),
  ]),
  Endpoint.new("/accounts/sign_in", "POST"),
  Endpoint.new("/accounts/password", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/accounts/password", "PUT", [
    Param.new("reset_password_token", "", "form"),
    Param.new("password", "", "form"),
    Param.new("password_confirmation", "", "form"),
  ]),
  Endpoint.new("/organizations/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/organizations/:organization_id/users", "GET", [
    Param.new("organization_id", "", "path"),
    Param.new("page", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/ruby/rails_strong_params/", {
  :techs     => 1,
  :endpoints => 23,
}, expected_endpoints)
tester.perform_tests

it "drops permit-list holders and roots, and routes `to:` on nested resources", tags: "functional" do
  update = tester.app.endpoints.find! { |e| e.url == "/articles/:id" && e.method == "PUT" }
  update.params.map(&.name).should_not contain("allowed")
  update.params.map(&.name).should_not contain("article")

  books = tester.app.endpoints.select(&.url.starts_with?("/books")).flat_map(&.params).map(&.name)
  books.should_not contain("wrong_a")
  books.should_not contain("isbn_wrong")

  users = tester.app.endpoints.find! { |e| e.url == "/organizations/:organization_id/users" }
  users.handler.not_nil!.name.should eq("organizations#users")
end

private def param_names(tester : FunctionalTester, method : String, url : String) : Array(String)
  tester.app.endpoints.find! { |e| e.method == method && e.url == url }.params.map(&.name)
end

it "reads permit lists and keys through a params helper or local, not the container key", tags: "functional" do
  param_names(tester, "POST", "/items").should eq(["name", "price"])
  param_names(tester, "PUT", "/items/:id").should eq(["id", "name", "price"])
  param_names(tester, "POST", "/orders").should eq(["quantity", "note"])
  param_names(tester, "POST", "/notes").should eq(["text", "color"])
end

it "gives a Devise action overridden without super none of Devise's params", tags: "functional" do
  param_names(tester, "POST", "/accounts/sign_in").should be_empty
end

it "keeps Devise's params for an override that calls super or a helper reading them", tags: "functional" do
  param_names(tester, "POST", "/accounts/password").should eq(["email"])
  param_names(tester, "PUT", "/accounts/password").should eq(["reset_password_token", "password", "password_confirmation"])
end
