require "../../func_spec.cr"

# Home Assistant's `HomeAssistantView`: each verb method is served at the
# class's `url`; `requires_auth` (True on the base) guards it.
entity = [Param.new("entity_id", "", "path")]
tester = FunctionalTester.new("fixtures/python/aiohttp_ha_view/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/states/{entity_id}", "GET", entity),
  Endpoint.new("/api/states/{entity_id}", "POST", entity + [Param.new("state", "", "json")]),
  Endpoint.new("/api/", "GET"),
])
tester.perform_tests

it "guards only the views that keep requires_auth", tags: "functional" do
  guarded = tester.endpoints.select { |ep| ep.tags.any? { |tag| tag.name == "auth" } }.map { |ep| "#{ep.method} #{ep.url}" }
  guarded.sort.should eq(["GET /api/states/{entity_id}", "POST /api/states/{entity_id}"])
end
