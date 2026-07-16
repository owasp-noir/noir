require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/unicode", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/tanstack_router_i18n/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "TanStack Router non-ASCII source attribution" do
  it "byte-counts line numbers and masks template-literal fakes past multi-byte chars" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/tanstack_router_i18n/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    # The multi-byte comment on line 3 must not skew the line attribution
    # of the route declared on line 4 (byte/char offset mix-up regression).
    unicode = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/unicode" }
    unicode.details.code_paths.first.line.should eq(4)

    # The createFileRoute-looking text inside the template literal must be
    # filtered by the (byte-indexed) literal mask even when multi-byte
    # chars precede it.
    app.endpoints.map(&.url).should_not contain("/fake")
  end
end
