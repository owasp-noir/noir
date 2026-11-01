require "../../func_spec.cr"

# Read the Docs' root URLconf: `urlpatterns = reduce(add, groups)` over a
# list of url lists, with members added by `groups.insert(0, ...)` and
# `groups.append([...])` under a setting; and `sum(parts, [])`. A list
# no group collects (`unused_urls`) is not mounted, and an `include()`
# inside a member keeps its prefix. A commented multi-line literal is
# read whole, a module-level rebinding drops the earlier members
# (`summed/stale/`), and both branches of a ternary member count.
FunctionalTester.new("fixtures/python/django_url_groups/", {
  :techs     => 1,
  :endpoints => 9,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/search/", "GET"),
  Endpoint.new("/dashboard/projects/", "GET"),
  Endpoint.new("/debug/", "GET"),
  Endpoint.new("/ext/", "GET"),
  Endpoint.new("/summed/a/", "GET"),
  Endpoint.new("/summed/b/", "GET"),
  Endpoint.new("/summed/c/", "GET"),
  Endpoint.new("/summed/d/", "GET"),
]).perform_tests
