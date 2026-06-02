require "../../func_spec.cr"

def applied_endpoint_with_callees(url, method, callees = [] of Callee)
  endpoint = Endpoint.new(url, method)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

# `/info` is served by `return apiInfo`; `apiInfo`'s body carries an inline
# `Proxy :: Proxy API` annotation, which must not stop it being treated as a
# definition.
info_callees = [
  Callee.new("buildInfo", line: 31),
]

# `H.rates s` — a qualified, applied server leaf resolves to the `rates` handler.
rates_callees = [
  Callee.new("lookupRates", line: 5),
]

# `H.allRates` — a qualified server leaf resolves to the `allRates` handler.
all_rates_callees = [
  Callee.new("loadAllRates", line: 10),
]

expected_endpoints = [
  applied_endpoint_with_callees("/info", "GET", info_callees),
  applied_endpoint_with_callees("/rates", "GET", rates_callees),
  applied_endpoint_with_callees("/rates/all", "GET", all_rates_callees),
]

tester = FunctionalTester.new("fixtures/haskell/servant_callees_applied/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "resolves Servant callees through a non-conventional server name and applied leaves" do
  info = tester.app.endpoints.find { |found| found.url == "/info" && found.method == "GET" }
  info.should_not be_nil
  info.try do |actual|
    actual.callees.map(&.name).should eq(info_callees.map(&.name))
  end

  rates = tester.app.endpoints.find { |found| found.url == "/rates" && found.method == "GET" }
  rates.should_not be_nil
  rates.try do |actual|
    actual.callees.map(&.name).should eq(rates_callees.map(&.name))
  end

  all_rates = tester.app.endpoints.find { |found| found.url == "/rates/all" && found.method == "GET" }
  all_rates.should_not be_nil
  all_rates.try do |actual|
    actual.callees.map(&.name).should eq(all_rates_callees.map(&.name))
  end
end
