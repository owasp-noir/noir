require "../../func_spec.cr"

# Swift structural-lexer regression test.
#
# Before the lexer:
# - Raw string literals containing route definitions (`#"app.get("fake_raw")"#`)
#   were kept verbatim and falsely emitted as phantom endpoints.
# - Closing braces inside raw multiline strings (`#""" ... """#`) or regular strings
#   truncated parameter lookahead and handler auth inspection prematurely.
#
# With `Noir::SwiftLexer`, comments and string contents are masked to spaces
# (delimiters kept), so phantom endpoints are avoided, and parameter/auth scans
# remain intact.

expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/custom/auth", "POST"),
]

FunctionalTester.new("fixtures/swift/lexer_repro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Swift lexer hostile shapes param and auth", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "preserves query parameters and handler auth across hostile strings" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/swift/lexer_repro/")])
    options["use_taggers"] = YAML::Any.new("swift_auth")
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    users = app.endpoints.find { |e| e.url == "/users/:id" }
    users.should_not be_nil
    users.not_nil!.params.map(&.name).should contain("q")

    auth = app.endpoints.find { |e| e.url == "/custom/auth" }
    auth.should_not be_nil
    auth.not_nil!.tags.map(&.name).should contain("auth")
  end
end
