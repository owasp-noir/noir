require "../../spec_helper"
require "json"
require "../../../src/cli/inspect"
require "../../../src/cli/commands/trace"
require "../../../src/cli/commands/reach"
require "../../../src/cli/commands/query"

private def endpoint(method : String, url : String, path : String? = nil, line : Int32? = nil, kind : String = "")
  details = path ? Details.new(PathInfo.new(path, line)) : Details.new
  details.technology = "go_gin"
  ep = Endpoint.new(url, method, details)
  ep.kind = kind
  ep
end

private def with_context(ep : Endpoint, guards = [] of String, sinks = [] of String, signals = [] of String, path : String? = nil) : Endpoint
  context = AIContext.new
  guards.each { |g| context.push_guard(AIContextEntry.new("guard", g, "heuristic", path: path, line: 3)) }
  sinks.each { |s| context.push_sink(AIContextEntry.new(s, "db.Exec", "callee", path: path, line: 80)) }
  signals.each { |s| context.push_signal(AIContextEntry.new(s, "x", "heuristic", path: path)) }
  context.push_signal(AIContextEntry.new("route_definition", "#{ep.method} #{ep.url}", "route", path: path))
  ep.ai_context = context
  ep
end

describe Noir::CLI::Inspect do
  describe ".parse_common" do
    it "takes its own flags and leaves the rest for scan" do
      common = Noir::CLI::Inspect.parse_common(["--from", "r.json", "-f", "text", "--full", "--limit=3", "--count", "./app", "-b", "x", "--only-techs", "go_gin"])
      common.from.should eq("r.json")
      common.format.should eq("text")
      common.full.should be_true
      common.limit.should eq(3)
      common.count.should be_true
      common.rest.should eq(["./app", "-b", "x", "--only-techs", "go_gin"])
      common.errors.should be_empty
    end

    it "rejects an unknown format and a bad limit" do
      common = Noir::CLI::Inspect.parse_common(["-f", "xml", "--limit", "0"])
      common.errors.size.should eq(2)
    end
  end

  describe ".split_positionals" do
    it "keeps a scan flag's value with the flag" do
      positionals, flags = Noir::CLI::Inspect.split_positionals(["GET", "/x", "-b", "./app", "--debug", "./other", "--exclude-path=foo", "--", "-weird"])
      positionals.should eq(["GET", "/x", "./other", "-weird"])
      flags.should eq(["-b", "./app", "--debug", "--exclude-path=foo"])
    end
  end

  describe ".trace" do
    endpoints = [
      endpoint("GET", "/users"),
      endpoint("GET", "/users/{id}"),
      endpoint("DELETE", "/users/:id"),
      endpoint("GET", "/files/*filepath"),
      endpoint("GET", "/posts/<int:pk>/comments"),
      endpoint("GET", "/docs/[...slug]"),
      endpoint("GET", "/static/**"),
      endpoint("GET", "/catalogue/<slug>/"),
      endpoint("OPTIONS", "/*"),
      endpoint("GET", "/u/*rest"),
      endpoint("GET", "/u/:id"),
      endpoint("GET", "http://example.com/health"),
      endpoint("GET", "^/re/(\\d+)/$", kind: "regex"),
      endpoint("ANY", "/any"),
    ]

    it "prefers an exact match and reports how it matched" do
      matches = Noir::CLI::Inspect.trace(endpoints, "GET", "/users/")
      matches.map(&.endpoint.url).should eq(["/users"])
      matches.first.matched_by.should eq("exact")
    end

    it "maps a concrete segment onto every placeholder syntax" do
      {
        "/users/42"                 => "/users/{id}",
        "/files/a/b/c.txt"          => "/files/*filepath",
        "/posts/7/comments"         => "/posts/<int:pk>/comments",
        "/docs/a/b"                 => "/docs/[...slug]",
        "/static/css/app.css"       => "/static/**",
        "/re/12/"                   => "^/re/(\\d+)/$",
        "/health"                   => "http://example.com/health",
        "/catalogue/blue-shirt_42/" => "/catalogue/<slug>/",
      }.each do |request, route|
        matches = Noir::CLI::Inspect.trace(endpoints, "GET", request)
        matches.map(&.endpoint.url).should eq([route]), "#{request} should match #{route}"
      end
    end

    it "filters by method, treating ANY as every method, and ignores method when nil" do
      Noir::CLI::Inspect.trace(endpoints, "DELETE", "/users/42").map(&.endpoint.url).should eq(["/users/:id"])
      Noir::CLI::Inspect.trace(endpoints, "POST", "/any").size.should eq(1)
      Noir::CLI::Inspect.trace(endpoints, nil, "/users/42").map(&.endpoint.url).should eq(["/users/{id}", "/users/:id", "/*"])
    end

    it "does not let a placeholder swallow more than one segment" do
      Noir::CLI::Inspect.trace(endpoints, "GET", "/users/42/extra").should be_empty
    end

    it "treats a bare * as a catch-all and ranks it below a specific route" do
      Noir::CLI::Inspect.trace(endpoints, "OPTIONS", "/a/b/c").map(&.matched_by).should eq(["wildcard"])
      matches = Noir::CLI::Inspect.trace(endpoints, "GET", "/u/5")
      matches.map(&.endpoint.url).should eq(["/u/:id", "/u/*rest"])
      matches.map(&.matched_by).should eq(["pattern", "wildcard"])
    end

    it "offers the nearest routes as candidates on a miss, forgiving case and typos" do
      rows = Noir::CLI::Inspect.candidates(endpoints, "/users/42/extra")
      rows.first(2).map(&.url).sort!.should eq(["/users/:id", "/users/{id}"])
      Noir::CLI::Inspect.candidates(endpoints, "/nothing/here").should be_empty
      Noir::CLI::Inspect.candidates(endpoints, "/Users/42").first.url.should start_with("/users/")
      Noir::CLI::Inspect.candidates(endpoints, "/userz").first.url.should eq("/users")
      Noir::CLI::Inspect.candidates(endpoints, "/posts/1/comment").first.url.should eq("/posts/<int:pk>/comments")
    end
  end

  describe ".reach" do
    handler = with_context(endpoint("PATCH", "/items/:id", "src/api/items.go", 18), guards: ["RequireAuth"], sinks: ["sql"], path: "src/api/items.go")
    handler.push_callee(Callee.new("repo.Update", "src/repo/items.go", 40))
    other = endpoint("GET", "/health", "src/api/health.go", 5)
    endpoints = [handler, other]

    it "matches a path suffix component-wise" do
      Noir::CLI::Inspect.path_matches?("src/api/items.go", "items.go").should be_true
      Noir::CLI::Inspect.path_matches?("src/api/items.go", "api/items.go").should be_true
      Noir::CLI::Inspect.path_matches?("./src/api/items.go", "src/api/items.go").should be_true
      Noir::CLI::Inspect.path_matches?("src/api/items.go", "tems.go").should be_false
      Noir::CLI::Inspect.path_matches?(nil, "items.go").should be_false
    end

    it "lists the evidence from the file, routes and callees alike" do
      rows = Noir::CLI::Inspect.reach(endpoints, "items.go", nil, false)
      rows.map(&.url).should eq(["/items/:id"])
      rows.first.via.map(&.kind).should eq(["route", "callee", "guard", "sink"]) # repo/items.go is items.go too

      rows = Noir::CLI::Inspect.reach(endpoints, "repo/items.go", nil, false)
      rows.first.via.map { |v| {v.kind, v.name} }.should eq([{"callee", "repo.Update"}])
    end

    it "orders evidence and rows by distance to the line without filtering" do
      rows = Noir::CLI::Inspect.reach(endpoints, "api/items.go", 78, false)
      rows.first.via.first.kind.should eq("sink")
      rows.first.nearest_line.should eq(80)
      rows.first.via.size.should eq(3)

      near_health = endpoint("GET", "/health2", "src/api/items.go", 400)
      rows = Noir::CLI::Inspect.reach(endpoints + [near_health], "api/items.go", 390, false)
      rows.map(&.url).should eq(["/health2", "/items/:id"])
    end

    it "names the declaration in the matched file, not the first merged copy" do
      ep = endpoint("GET", "/ping", "other/hello.go", 31)
      ep.details.add_path(PathInfo.new("basic/main.go", 17))
      rows = Noir::CLI::Inspect.reach([ep], "basic/main.go", nil, false)
      rows.first.path.should eq("basic/main.go")
      rows.first.line.should eq(17)
    end
  end

  describe ".query" do
    guarded = with_context(endpoint("GET", "/admin/users", "src/admin.go", 1), guards: ["RequireAuth"], sinks: ["sql"], signals: ["idor_review"])
    guarded.add_tag(Tag.new("auth", "", "hunt"))
    open = with_context(endpoint("POST", "/api/v1/items", "src/items.go", 1), sinks: ["command"])
    open.push_param(Param.new("name", "", "json"))
    bare = endpoint("GET", "/health", "src/health.go", 1)
    endpoints = [guarded, open, bare]

    it "ANDs filters and ORs comma lists" do
      f = Noir::CLI::QueryCommand.parse_filters(["--method", "GET,POST", "--sink", "any"]).filters
      Noir::CLI::Inspect.query(endpoints, f, false).map(&.url).should eq(["/admin/users", "/api/v1/items"])

      f = Noir::CLI::QueryCommand.parse_filters(["--method=POST", "--sink", "sql"]).filters
      Noir::CLI::Inspect.query(endpoints, f, false).should be_empty
    end

    it "tells guarded from unguarded, counting a missing context or a rate limiter as unguarded" do
      limited = endpoint("POST", "/2fa", "src/2fa.go", 1)
      ctx = AIContext.new
      ctx.push_guard(AIContextEntry.new("rate_limit_guard", "rateLimit"))
      limited.ai_context = ctx
      all = endpoints + [limited]
      f = Noir::CLI::QueryCommand.parse_filters(["--no-guard"]).filters
      Noir::CLI::Inspect.query(all, f, false).map(&.url).should eq(["/api/v1/items", "/health", "/2fa"])
      f = Noir::CLI::QueryCommand.parse_filters(["--guard"]).filters
      Noir::CLI::Inspect.query(all, f, false).map(&.url).should eq(["/admin/users"])
      Noir::CLI::QueryCommand.parse_filters(["--guard", "--no-guard"]).errors.should eq(["--guard and --no-guard are exclusive"])
    end

    it "ignores restating signals for --signal any and matches a relative path glob as a suffix" do
      f = Noir::CLI::QueryCommand.parse_filters(["--signal", "any"]).filters
      Noir::CLI::Inspect.query(endpoints, f, false).map(&.url).should eq(["/admin/users"])
      f = Noir::CLI::QueryCommand.parse_filters(["--path", "src/*"]).filters
      Noir::CLI::Inspect.query([endpoint("GET", "/x", "corpus/app/src/a.go", 1)], f, false).size.should eq(1)
    end

    it "warns about filter kinds no endpoint carries and about a report without ai_context" do
      f = Noir::CLI::QueryCommand.parse_filters(["--sink", "file", "--signal", "any"]).filters
      Noir::CLI::Inspect.filter_warnings(endpoints, f).should eq(["no endpoint carries sink kind file; kinds in this report: command, sql"])
      Noir::CLI::Inspect.filter_warnings([bare], f).first.should start_with("no endpoint carries ai_context")
      Noir::CLI::Inspect.filter_warnings(endpoints, Noir::CLI::QueryCommand.parse_filters(["--sink", "sql"]).filters).should be_empty
    end

    it "matches url/path as a glob or a substring, tags, params and signals" do
      {
        ["--url", "/api/**"]                    => ["/api/v1/items"],
        ["--url", "admin"]                      => ["/admin/users"],
        ["--path", "src/health.go"]             => ["/health"],
        ["--tag", "auth"]                       => ["/admin/users"],
        ["--param", "name"]                     => ["/api/v1/items"],
        ["--param-type", "json"]                => ["/api/v1/items"],
        ["--signal", "idor_review"]             => ["/admin/users"],
        ["--tech", "go_gin", "--method", "GET"] => ["/admin/users", "/health"],
      }.each do |argv, expected|
        f = Noir::CLI::QueryCommand.parse_filters(argv).filters
        Noir::CLI::Inspect.query(endpoints, f, false).map(&.url).should eq(expected), argv.join(" ")
      end
    end

    it "passes everything it does not own through to scan" do
      parsed = Noir::CLI::QueryCommand.parse_filters(["--no-guard", "./app", "-b", "x", "--debug"])
      parsed.rest.should eq(["./app", "-b", "x", "--debug"])
      Noir::CLI::QueryCommand.parse_filters(["--sink"]).errors.should eq(["--sink requires a value"])
    end
  end

  describe Noir::CLI::Inspect::Row do
    it "projects the endpoint and omits empty buckets" do
      ep = with_context(endpoint("GET", "/admin/users", "src/admin.go", 7), guards: ["RequireAuth"], signals: ["idor_review"])
      ep.push_callee(Callee.new("db.Query"))
      json = JSON.parse(Noir::CLI::Inspect::Row.compact(ep).to_json)
      json["path"].should eq("src/admin.go")
      json["line"].should eq(7)
      json["tech"].should eq("go_gin")
      json["guards"].should eq(["RequireAuth"])
      json["signals"].should eq(["idor_review"]) # route_definition restates the route
      json["callees"].should eq(["db.Query"])
      json["sinks"]?.should be_nil
      json["params"]?.should be_nil
    end

    it "carries the unchanged endpoint when full" do
      ep = endpoint("GET", "/x", "a.go", 1)
      json = JSON.parse(Noir::CLI::Inspect::Row.full(ep).to_json)
      json["endpoint"]["details"]["code_paths"][0]["path"].should eq("a.go")
      json["path"]?.should be_nil
    end
  end

  describe ".load_report" do
    it "reads a json document and a jsonl stream alike, skipping non-endpoint lines" do
      ep = endpoint("GET", "/x", "a.go", 1)
      json_path = File.tempname("noir-inspect", ".json")
      jsonl_path = File.tempname("noir-inspect", ".jsonl")
      File.write(json_path, {"endpoints" => [ep], "passive_results" => [] of String, "errors" => [] of String}.to_json)
      File.write(jsonl_path, "#{ep.to_json}\n{\"id\":\"secret\",\"info\":{}}\n{\"tech\":\"x\",\"message\":\"m\"}\n")
      begin
        Noir::CLI::Inspect.load_report(json_path).map(&.url).should eq(["/x"])
        Noir::CLI::Inspect.load_report(jsonl_path).map(&.url).should eq(["/x"])
      ensure
        File.delete?(json_path)
        File.delete?(jsonl_path)
      end
    end
  end

  describe ".emit" do
    it "returns 1 for no rows, honours --limit and --count" do
      rows = [Noir::CLI::Inspect::Row.new("GET", "/a"), Noir::CLI::Inspect::Row.new("GET", "/b")]
      io = IO::Memory.new
      Noir::CLI::Inspect.emit([] of Noir::CLI::Inspect::Row, Noir::CLI::Inspect.parse_common([] of String), io).should eq(1)
      io.to_s.should eq("")

      io = IO::Memory.new
      Noir::CLI::Inspect.emit(rows, Noir::CLI::Inspect.parse_common(["--limit", "1"]), io).should eq(0)
      io.to_s.lines.size.should eq(1)

      io = IO::Memory.new
      Noir::CLI::Inspect.emit(rows, Noir::CLI::Inspect.parse_common(["--count", "-f", "text"]), io)
      io.to_s.should eq("2\n")
    end
  end
end

describe Noir::CLI::TraceCommand do
  it "reads the target as one quoted argument, two arguments, or a bare path" do
    target, rest = Noir::CLI::TraceCommand.parse_target(["post /x", "./app"])
    target.not_nil!.method.should eq("POST")
    target.not_nil!.path.should eq("/x")
    rest.should eq(["./app"])

    target, rest = Noir::CLI::TraceCommand.parse_target(["GET", "/x", "./app"])
    target.not_nil!.method.should eq("GET")
    rest.should eq(["./app"])

    target, rest = Noir::CLI::TraceCommand.parse_target(["/x"])
    target.not_nil!.method.should be_nil
    rest.should be_empty

    Noir::CLI::TraceCommand.parse_target(["./app"])[0].should be_nil
    Noir::CLI::TraceCommand.parse_target(["GET"])[0].should be_nil
  end
end

describe Noir::CLI::ReachCommand do
  it "splits a trailing :line only when it is a number" do
    Noir::CLI::ReachCommand.parse_target("src/a.go:42").should eq({"src/a.go", 42})
    Noir::CLI::ReachCommand.parse_target("src/a.go").should eq({"src/a.go", nil})
    Noir::CLI::ReachCommand.parse_target("C:/x/a.go").should eq({"C:/x/a.go", nil})
  end
end
