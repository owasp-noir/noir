require "../../func_spec.cr"

# Livewire actions and writable properties all go through `POST
# /livewire/update`; the fragment names `<component>.<action>`. Lifecycle
# hooks, `#[Computed]` methods, `#[Locked]` / static properties and Blade
# view components (`Illuminate\View\Component`) are not endpoints.
FunctionalTester.new("fixtures/php/livewire/", {
  :techs     => 3,
  :endpoints => 4,
}, [
  Endpoint.new("/livewire/update#edit-post.save", "POST", [
    Param.new("title", "", "json"), Param.new("body", "", "json"),
  ]),
  Endpoint.new("/livewire/update#edit-post.delete", "POST", [
    Param.new("title", "", "json"), Param.new("body", "", "json"), Param.new("confirm", "", "json"),
  ]),
  Endpoint.new("/livewire/update#posts.search-posts", "POST", [Param.new("query", "", "json")]),
  Endpoint.new("/livewire/update#counter.increment", "POST", [
    Param.new("count", "", "json"), Param.new("by", "", "json"),
  ]),
]).perform_tests

# `Livewire::setUpdateRoute` moves the endpoint.
FunctionalTester.new("fixtures/php/livewire_update_route/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/custom/livewire/update#counter.increment", "POST", [Param.new("count", "", "json")]),
], {
  "only_techs" => YAML::Any.new("php_livewire"),
}).perform_tests
