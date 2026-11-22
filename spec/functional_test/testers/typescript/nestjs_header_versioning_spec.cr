require "../../func_spec.cr"

# Both versions have the same method and URL. Match the newer handler
# for the param assertion while the spec below checks both versions.
private class NestjsHeaderVersioningTester < FunctionalTester
  private def actual_endpoint(expected : Endpoint) : Endpoint
    return super unless expected.method == "GET" && expected.url == "/v2/schedules"

    endpoints.find do |endpoint|
      endpoint.method == expected.method && endpoint.url == expected.url &&
        endpoint.handler.try(&.name) == "SchedulesController_2024_06_01.list"
    end || fail("Missing versioned GET /v2/schedules endpoint")
  end
end

# `enableVersioning({ type: VersioningType.CUSTOM, ... })` reads the version
# from a header: no `v<version>` URL segment, and Nest's trailing-slash strip
# applies (`@Get("/")` on `/v2/me`).
expected_endpoints = [
  Endpoint.new("/v2/schedules", "GET", [Param.new("x-api-version", "", "header")]),
  Endpoint.new("/v2/schedules/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v2/me", "GET"),
  # `@Controller({ path: "/v2/verified-resources", })`: the trailing comma
  # used to drop the prefix.
  Endpoint.new("/v2/verified-resources/emails", "GET"),
]

# The two `/v2/schedules` controllers stay two rows.
NestjsHeaderVersioningTester.new("fixtures/typescript/nestjs_header_versioning/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests

describe "ts_nestjs header versioning", tags: "functional" do
  it "keeps the default version's row plain and names the other version's header" do
    tester = FunctionalTester.new("fixtures/typescript/nestjs_header_versioning/", {:techs => 1}, [] of Endpoint)
    rows = tester.endpoints.select { |ep| ep.url == "/v2/schedules" }
    versions = rows.to_h do |ep|
      {ep.handler.try(&.name), ep.params.select(&.param_type.==("header")).map { |p| "#{p.name}=#{p.value}" }}
    end
    versions.should eq({
      "SchedulesController_2024_01_01.list" => [] of String,
      "SchedulesController_2024_06_01.list" => ["x-api-version=2024-06-01"],
    })
  end
end
