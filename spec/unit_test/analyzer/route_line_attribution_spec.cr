require "../../spec_helper"
require "../../../src/models/noir"

# `code_paths` is what sends a reader to the route: an endpoint whose line
# points somewhere else is a wrong answer even when the URL and method are
# right. The functional testers compare endpoints by URL/method/params and
# never look at the line, so every one of the skews below passed a green
# suite. These pin the line against the checked-in fixtures.
private def scan_fixture(relative : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(File.join(__DIR__, "../../functional_test/fixtures", relative))])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def line_of(endpoints : Array(Endpoint), method : String, url : String, file_suffix : String) : Int32?
  endpoints.each do |endpoint|
    next unless endpoint.method == method && endpoint.url == url
    endpoint.details.code_paths.each do |code_path|
      return code_path.line if code_path.path.ends_with?(file_suffix)
    end
  end
  nil
end

describe "route line attribution" do
  it "points a Grails verbless mapping at its own line, not the previous one" do
    # The verbless paren-form and closure-form patterns open with
    # `(?:^|\n)\s*`, so match offset 0 is the newline that ENDS the previous
    # line — and greedy `\s*` then swallows every blank and comment-blanked
    # line after it. `/api/users` (fixture line 7) was reported at line 4 and
    # `/api/legacy` (line 20) at line 10.
    endpoints = scan_fixture("groovy/grails")
    suffix = "grails-app/conf/UrlMappings.groovy"

    line_of(endpoints, "POST", "/api/users", suffix).should eq(7)
    line_of(endpoints, "GET", "/api/orders", suffix).should eq(10)
    line_of(endpoints, "POST", "/api/legacy", suffix).should eq(20)
    line_of(endpoints, "GET", "/api/reports", suffix).should eq(29)
    line_of(endpoints, "GET", "/api/profile", suffix).should eq(37)

    # The verb-prefixed form never had the skew and must keep its line.
    line_of(endpoints, "GET", "/api/health", suffix).should eq(3)
  end

  it "points a Jetzig resourceful action at its `pub fn`" do
    # `ACTION_FN_RE` opens with `(?:^|[^A-Za-z0-9_.])`, so a match at the
    # start of a line begins on the previous line's newline: every action was
    # reported one line high.
    endpoints = scan_fixture("zig/jetzig")
    suffix = "src/app/views/posts.zig"

    line_of(endpoints, "GET", "/posts", suffix).should eq(4)
    line_of(endpoints, "GET", "/posts/:id", suffix).should eq(10)
  end

  it "points an inline Yesod parseRoutes route at its file line" do
    # The quasi-quote body is processed as a standalone document, so without
    # a line offset every route was reported at its position *within the
    # quote* — which for the usual `Foundation.hs` layout landed in the
    # module header.
    endpoints = scan_fixture("haskell/yesod")
    suffix = "src/Foundation.hs"

    line_of(endpoints, "GET", "/", suffix).should eq(11)
    line_of(endpoints, "GET", "/blog/:text", suffix).should eq(12)
    line_of(endpoints, "GET", "/api/health", suffix).should eq(14)
    line_of(endpoints, "PUT", "/api/users/:user_id", suffix).should eq(15)
  end
end
