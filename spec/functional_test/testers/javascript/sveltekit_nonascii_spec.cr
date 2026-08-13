require "../../func_spec.cr"

# Line numbers must survive multi-byte source.
#
# `MatchData#begin` returns a CHAR index. Four JS analyzers fed it straight
# into `content.to_slice[0, index]`, which reads it as a BYTE length — so
# every non-ASCII character before the match shortened the slice, fewer
# newlines were counted, and the reported line came out too low. Three lines
# of Korean/Japanese/Spanish comments were enough to move a route from line 5
# to line 2.
#
# The fixture is deliberately mixed-script: Hangul (3 bytes/char), Kana
# (3 bytes), emoji (4 bytes) and Latin-1 accents (2 bytes), so a fix that
# only handles one width does not pass.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
]

FunctionalTester.new("fixtures/javascript/sveltekit_nonascii/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "SvelteKit line numbers with multi-byte source" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports the line the route is actually on" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/sveltekit_nonascii/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users" }
    get.details.code_paths.first.line.should eq(5)

    post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    post.details.code_paths.first.line.should eq(9)
  end
end
