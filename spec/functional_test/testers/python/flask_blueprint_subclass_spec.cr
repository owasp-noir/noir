require "../../func_spec.cr"

# A Blueprint subclass (`class EventBlueprint(Blueprint)`) is built with
# Flask's constructor, so its url_prefix prefixes every route registered on
# the instance. Indico's IndicoBlueprint is the real-world case.
expected_endpoints = [
  Endpoint.new("/event/<int:event_id>/manage", "GET", [Param.new("event_id", "", "path")]),
  Endpoint.new("/event/<int:event_id>/registration/", "GET", [Param.new("event_id", "", "path")]),
]

FunctionalTester.new("fixtures/python/flask_blueprint_subclass/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
