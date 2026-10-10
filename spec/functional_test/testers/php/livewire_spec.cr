require "../../func_spec.cr"

# Livewire actions and writable properties all go through `POST
# /livewire/update`; the fragment names `<component>.<action>`. Lifecycle
# hooks, `#[Computed]` methods, `#[Locked]` / static members, abstract base
# components and Blade view components (`Illuminate\View\Component`) are
# not endpoints; a commented-out `#[Locked]` does not lock. Volt
# `Volt::route(...)` full-page components are GET routes, group prefixes
# included.
FunctionalTester.new("fixtures/php/livewire/", {
  :techs     => 3,
  :endpoints => 7,
}, [
  Endpoint.new("/livewire/update#edit-post.save", "POST", [
    Param.new("title", "", "json"), Param.new("body", "", "json"), Param.new("draftId", "", "json"),
  ]),
  Endpoint.new("/livewire/update#edit-post.delete", "POST", [
    Param.new("title", "", "json"), Param.new("body", "", "json"), Param.new("draftId", "", "json"),
    Param.new("confirm", "", "json"),
  ]),
  Endpoint.new("/livewire/update#posts.search-posts", "POST", [Param.new("query", "", "json")]),
  Endpoint.new("/livewire/update#counter.increment", "POST", [
    Param.new("count", "", "json"), Param.new("by", "", "json"),
  ]),
  # `public $a, $b = [...], $c;` declares all three; `public final function` is an action.
  Endpoint.new("/livewire/update#tag-picker.pick", "POST", [
    Param.new("tags", "", "json"), Param.new("options", "", "json"), Param.new("selected", "", "json"),
    Param.new("tag", "", "json"),
  ]),
  Endpoint.new("/counter", "GET"),
  Endpoint.new("/admin/posts/{post}", "GET", [Param.new("post", "", "path")]),
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

# Two Laravel apps under one scan base: only `custom/` calls
# `setUpdateRoute`, so `plain/`'s component stays on the default route.
FunctionalTester.new("fixtures/php/livewire_multi_app/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/custom/livewire/update#counter.increment", "POST", [Param.new("count", "", "json")]),
  Endpoint.new("/livewire/update#toggle.flip", "POST", [Param.new("on", "", "json")]),
], {
  "only_techs" => YAML::Any.new("php_livewire"),
}).perform_tests
