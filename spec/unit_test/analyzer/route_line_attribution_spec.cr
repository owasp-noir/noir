require "../../spec_helper"
require "../../../src/models/noir"

# `code_paths` is what sends a reader to the route: an endpoint whose line
# points somewhere else is a wrong answer even when the URL and method are
# right. The functional testers compare endpoints by URL/method/params and
# never look at the line, so every one of the skews below passed a green
# suite.
#
# Assertions name the text the line must hold rather than a line number, so
# editing a shared fixture cannot fail this spec from a distance — the point
# being tested is "the reported line holds the route", not "the route is on
# line 7".
private def scan_fixture(relative : String) : Array(Endpoint)
  # `clear_all`, before the scan and not merely `reset_files` after it, for
  # the reason `FunctionalTester#ensure_scanned` documents: `CodeLocator` is a
  # process-wide singleton and under `--order random` this example can follow
  # any other scan. `reset_files` leaves `@s_map`/`@a_map` behind.
  CodeLocator.instance.clear_all

  options = create_test_options
  # Spelled relative, exactly like the functional harness: skip filters and
  # `base_relative_path` read the full path, so an absolute base would make
  # this spec depend on where the checkout happens to sit.
  options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/#{relative}")])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
end

# The source line an endpoint points at, in the file whose path ends with
# `file_suffix`. Raises rather than returning nil so a missing endpoint reads
# as "not found" instead of as a confusing comparison against nil.
private def source_line_for(endpoints : Array(Endpoint), method : String, url : String, file_suffix : String) : String
  endpoints.each do |endpoint|
    next unless endpoint.method == method && endpoint.url == url
    endpoint.details.code_paths.each do |code_path|
      next unless code_path.path.ends_with?(file_suffix)
      line = code_path.line || 0
      lines = File.read_lines(code_path.path)
      raise "#{method} #{url}: line #{line} is outside #{code_path.path} (#{lines.size} lines)" unless 1 <= line <= lines.size
      return lines[line - 1]
    end
  end
  raise "no #{method} #{url} endpoint with a code path in *#{file_suffix}"
end

describe "route line attribution" do
  it "points a Grails mapping at its own line" do
    # Both verbless patterns opened with `(?:^|\n)\s*`, so match offset 0 was
    # the newline that ENDS the previous line — and greedy `\s*` then swallowed
    # every blank and comment-blanked line after it, putting `/api/users`
    # three lines high. The verb-prefixed form has the same trap in its
    # optional `name <id>:` prefix, which `\s*` lets sit on an earlier line.
    endpoints = scan_fixture("groovy/grails")
    suffix = "grails-app/conf/UrlMappings.groovy"

    source_line_for(endpoints, "POST", "/api/users", suffix).should contain("\"/api/users\"")
    source_line_for(endpoints, "GET", "/api/orders", suffix).should contain("\"/api/orders\"")
    source_line_for(endpoints, "POST", "/api/legacy", suffix).should contain("\"/api/legacy\"")
    source_line_for(endpoints, "GET", "/api/reports", suffix).should contain("\"/api/reports\"")
    source_line_for(endpoints, "GET", "/api/profile", suffix).should contain("\"/api/profile\"")
    source_line_for(endpoints, "GET", "/api/health", suffix).should contain("\"/api/health\"")
  end

  it "points a Jetzig resourceful action at its `pub fn`" do
    # `ACTION_FN_RE` consumed a leading character, so a match at the start of a
    # line began on the previous line's newline: every action was one line
    # high.
    endpoints = scan_fixture("zig/jetzig")
    suffix = "src/app/views/posts.zig"

    source_line_for(endpoints, "GET", "/posts", suffix).should contain("pub fn index(")
    source_line_for(endpoints, "GET", "/posts/:id", suffix).should contain("pub fn get(")
    source_line_for(endpoints, "DELETE", "/posts/:id", suffix).should contain("pub fn delete(")
  end

  it "points an inline Yesod parseRoutes route at its file line" do
    # The quasi-quote body is processed as a standalone document, so without a
    # line offset every route was reported at its position *within the quote* —
    # which for the usual `Foundation.hs` layout landed in the module header.
    endpoints = scan_fixture("haskell/yesod")
    suffix = "src/Foundation.hs"

    source_line_for(endpoints, "GET", "/", suffix).should contain("HomeR")
    source_line_for(endpoints, "GET", "/blog/:text", suffix).should contain("BlogPostR")
    source_line_for(endpoints, "GET", "/api/health", suffix).should contain("HealthR")
    source_line_for(endpoints, "PUT", "/api/users/:user_id", suffix).should contain("UserR")
  end
end
