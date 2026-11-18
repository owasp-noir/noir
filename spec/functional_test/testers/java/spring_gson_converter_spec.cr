require "../../func_spec.cr"

# A registered `GsonHttpMessageConverter` reads JSON bodies by field name, so
# a Lombok `boolean isHidden` keeps `isHidden` as its JSON key; form and
# query binding still use the bean property `hidden`.
tester = FunctionalTester.new("fixtures/java/spring_gson_converter/", {
  :techs     => 1,
  :endpoints => 2,
}, [] of Endpoint)
tester.perform_tests

it "keeps the field name as the JSON key under Gson", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /items", ["hidden:query", "name:query"]},
    {"POST /items", ["isHidden:json", "name:json"]},
  ])
end
