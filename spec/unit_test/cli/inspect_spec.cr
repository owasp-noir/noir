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
      endpoint("GET", "/media/<path:path>"),
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
        "/media/img/a.png"          => "/media/<path:path>",
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

    it "puts a route declared for the method before an ANY one at the same path" do
      routes = [endpoint("ANY", "/login"), endpoint("POST", "/login")]
      Noir::CLI::Inspect.trace(routes, "POST", "/login").map(&.endpoint.method).should eq(["POST", "ANY"])
      Noir::CLI::Inspect.trace(routes, nil, "/login").map(&.endpoint.method).should eq(["ANY", "POST"])
    end

    it "holds typed placeholders to their type" do
      typed = [endpoint("GET", "/d/<uuid:id>/docs"), endpoint("GET", "/n/{id:int}"), endpoint("GET", "/g/{id:guid}")]
      Noir::CLI::Inspect.trace(endpoints, "GET", "/posts/abc/comments").should be_empty
      Noir::CLI::Inspect.trace(typed, "GET", "/d/5a6b7c8d-9e0f-4a1b-8c2d-3e4f5a6b7c8d/docs").size.should eq(1)
      Noir::CLI::Inspect.trace(typed, "GET", "/d/kb-legal-docs/docs").should be_empty
      Noir::CLI::Inspect.trace(typed, "GET", "/n/42").size.should eq(1)
      Noir::CLI::Inspect.trace(typed, "GET", "/n/forty").should be_empty
      Noir::CLI::Inspect.trace(typed, "GET", "/g/5a6b7c8d9e0f4a1b8c2d3e4f5a6b7c8d").size.should eq(1)
    end

    it "reads path-to-regexp optional segments and regex constraints" do
      routes = [
        endpoint("GET", "/posts/:id?"),
        endpoint("GET", "/files/:name(\\d+)"),
        endpoint("GET", "/hono/:id{[0-9]+}"),
        endpoint("GET", "/v5/posts{/:id}"),
        endpoint("GET", "/tree/:path+"),
      ]
      trace = ->(path : String) { Noir::CLI::Inspect.trace(routes, "GET", path).map(&.endpoint.url) }
      trace.call("/posts").should eq(["/posts/:id?"])
      trace.call("/posts/5").should eq(["/posts/:id?"])
      trace.call("/posts/5/x").should be_empty
      trace.call("/files/42").should eq(["/files/:name(\\d+)"])
      trace.call("/files/abc").should be_empty
      trace.call("/hono/7").should eq(["/hono/:id{[0-9]+}"])
      trace.call("/hono/seven").should be_empty
      trace.call("/v5/posts").should eq(["/v5/posts{/:id}"])
      trace.call("/v5/posts/9").should eq(["/v5/posts{/:id}"])
      trace.call("/tree/a/b").should eq(["/tree/:path+"])
    end

    it "holds a chi / gorilla regex constraint to its regex" do
      routes = [
        endpoint("GET", "/{owner}/{repo}/{type:issues}/{index}"),
        endpoint("POST", "/{owner}/{repo}/action/{action:star|unstar}"),
        endpoint("GET", "/{owner}/{repo}/objects/{head:[0-9a-f]{2}}/{hash:^[0-9a-f]{38,62}$}"),
        endpoint("GET", "/{owner}/{repo}/pack-{file:[0-9a-f]{40}}.pack"),
        endpoint("GET", "/bad/{x:[unclosed}"),
        endpoint("GET", "/{owner}/{repo}/contents/*"),
      ]
      trace = ->(method : String, path : String) { Noir::CLI::Inspect.trace(routes, method, path).map(&.endpoint.url) }
      trace.call("GET", "/o/r/issues/12").should eq(["/{owner}/{repo}/{type:issues}/{index}"])
      trace.call("GET", "/o/r/info/refs").should be_empty
      trace.call("GET", "/o/r/myissues/12").should be_empty
      trace.call("POST", "/o/r/action/unstar").size.should eq(1)
      trace.call("POST", "/o/r/action/watch").should be_empty
      trace.call("GET", "/o/r/objects/ab/#{"c" * 38}").size.should eq(1)
      trace.call("GET", "/o/r/objects/abc/#{"c" * 38}").should be_empty
      trace.call("GET", "/o/r/pack-#{"a" * 40}.pack").size.should eq(1)
      trace.call("GET", "/bad/anything").should eq(["/bad/{x:[unclosed}"])
      trace.call("GET", "/o/r/contents/docs/README.md").should eq(["/{owner}/{repo}/contents/*"])
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

    it "names nearby routes when only a catch-all answered, and not otherwise" do
      typo = Noir::CLI::Inspect.trace(endpoints, "OPTIONS", "/userz/42")
      typo.map(&.matched_by).should eq(["wildcard"])
      rows = Noir::CLI::Inspect.wildcard_only_candidates(endpoints, typo, "/userz/42")
      rows.first.url.should start_with("/users")
      rows.map(&.url).should_not contain("/*")
      hit = Noir::CLI::Inspect.trace(endpoints, nil, "/users/42")
      Noir::CLI::Inspect.wildcard_only_candidates(endpoints, hit, "/users/42").should be_empty
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

    it "names the handler's file as evidence and projects it onto the row" do
      ep = endpoint("GET", "/u", "config/routes.rb", 4)
      ep.handler = Handler.new("users#show", "app/controllers/users_controller.rb", 12)
      rows = Noir::CLI::Inspect.reach([ep], "users_controller.rb", nil, false)
      rows.first.via.map { |v| {v.kind, v.name, v.line} }.should eq([{"handler", "users#show", 12}])
      rows.first.path.should eq("config/routes.rb")
      JSON.parse(rows.first.to_json)["handler"]["line"].should eq(12)
      rows.first.to_text.should contain("handler=users#show@app/controllers/users_controller.rb:12")

      f = Noir::CLI::QueryCommand.parse_filters(["--handler", "users#"]).filters
      Noir::CLI::Inspect.query([ep, endpoint("GET", "/v")], f, false).map(&.url).should eq(["/u"])
      f = Noir::CLI::QueryCommand.parse_filters(["--handler", "controllers/*"]).filters
      Noir::CLI::Inspect.query([ep], f, false).size.should eq(1)
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
      Noir::CLI::Inspect.filter_warnings(endpoints, f).should eq(["no endpoint carries sink kind file; in this report: command, sql"])
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

describe "query verb reliability (#3139)" do
  it "prints the one text line for --full rows, with matched_by" do
    ep = with_context(endpoint("GET", "/u/:id", "a.go", 3), guards: ["RequireAuth"])
    row = Noir::CLI::Inspect::Row.full(ep)
    row.matched_by = "pattern"
    row.to_text.should eq("GET /u/:id  a.go:3  go_gin  matched_by=pattern  guards=RequireAuth")
  end

  it "shows only auth guards on the compact row, as --guard counts them" do
    ep = endpoint("POST", "/2fa", "a.go", 1)
    ctx = AIContext.new
    ctx.push_guard(AIContextEntry.new("rate_limit_guard", "rateLimit"))
    ep.ai_context = ctx
    Noir::CLI::Inspect::Row.compact(ep).guards.should be_empty
  end

  it "names the first declaration outside a copy directory and counts the copies" do
    ep = endpoint("GET", "/api/Users", "app/data/static/codefixes/x_1.ts", 10)
    ep.details.code_paths << PathInfo.new("app/data/static/codefixes/x_2.ts", 10)
    ep.details.code_paths << PathInfo.new("app/server.ts", 391)
    row = Noir::CLI::Inspect::Row.compact(ep)
    {row.path, row.line, row.declarations}.should eq({"app/server.ts", 391, 3})
    # Django lists the declaring app config first and its include chain after.
    chain = endpoint("GET", "/basket/saved/", "src/oscar/apps/basket/apps.py")
    chain.details.code_paths << PathInfo.new("src/oscar/config.py")
    chain.details.code_paths << PathInfo.new("sandbox/urls.py")
    Noir::CLI::Inspect::Row.compact(chain).path.should eq("src/oscar/apps/basket/apps.py")
    Noir::CLI::Inspect::Row.compact(endpoint("GET", "/one", "a.go", 1)).declarations.should be_nil
  end

  it "globs across / and treats {id} as literal; a relative path glob matches from any /" do
    g = ->(p : String, v : String) { Noir::CLI::Inspect.glob_or_substring?(p, v) }
    g.call("*users*", "/accounts/users/").should be_true
    g.call("/owners/{ownerId}/*", "/owners/{ownerId}/pets/new").should be_true
    g.call("/owners/{ownerId}/*", "/owners/find").should be_false
    g.call("/api/v?", "/api/v1").should be_true
    g.call("users", "/api/users").should be_true # substring
    g.call("[", "/x[").should be_true            # unbalanced class: literal
    pg = ->(p : String, v : String) { Noir::CLI::Inspect.path_glob?(p, v) }
    pg.call("routes/*", "corpus/app/routes/login.ts").should be_true
    pg.call("routes/*.go", "corpus/app/routes/login.ts").should be_false
    pg.call("/corpus/*", "corpus/app/x.go").should be_false
  end

  it "traces HEAD to the GET route" do
    get = endpoint("GET", "/owners", "a.java", 1)
    Noir::CLI::Inspect.trace([get], "HEAD", "/owners").map(&.matched_by).should eq(["exact"])
    Noir::CLI::Inspect.trace([get], "POST", "/owners").should be_empty
  end

  it "requires one parameter to satisfy --param and --param-type together" do
    ep = endpoint("PATCH", "/users/{user_id}", "u.py", 1)
    ep.push_param(Param.new("user_id", "", "path"))
    ep.push_param(Param.new("email", "", "json"))
    both = Noir::CLI::QueryCommand.parse_filters(["--param", "email", "--param-type", "path"]).filters
    Noir::CLI::Inspect.query([ep], both, false).should be_empty
    same = Noir::CLI::QueryCommand.parse_filters(["--param", "email", "--param-type", "json"]).filters
    Noir::CLI::Inspect.query([ep], same, false).size.should eq(1)
  end

  it "warns for every filter value nobody carries, and explains restating signals" do
    ep = with_context(endpoint("GET", "/x", "a.go", 1), sinks: ["sql"])
    ep.add_tag(Tag.new("auth", "", "hunt"))
    f = Noir::CLI::QueryCommand.parse_filters(["--tag", "nope", "--method", "PUT", "--signal", "route_definition"]).filters
    Noir::CLI::Inspect.filter_warnings([ep], f).should eq([
      "no endpoint carries method PUT; in this report: GET",
      "no endpoint carries tag nope; in this report: auth",
      "signal route_definition restates the row's method, url or tech and does not filter",
    ])
  end

  it "rejects an empty filter value and accepts --validator" do
    Noir::CLI::QueryCommand.parse_filters(["--sink", ""]).errors.should eq(["--sink requires a value"])
    Noir::CLI::QueryCommand.parse_filters(["--validator", "any"]).filters.validators.should eq(["any"])
  end

  it "names unknown scan flags before scanning" do
    Noir::CLI::Inspect.unknown_flags(["-b", "x", "--exclude-path", "y", "--bogus", "--no-gaurd=1"]).should eq(["--bogus", "--no-gaurd=1"])
  end

  it "keeps the file on via entries outside the row's file and drops duplicates" do
    ep = endpoint("GET", "/", "apps/a/main.go", 5)
    ep.details.code_paths << PathInfo.new("apps/b/main.go", 9)
    ep.details.code_paths << PathInfo.new("apps/b/main.go", 9)
    ep.push_callee(Callee.new("render", "apps/b/main.go", 12))
    rows = Noir::CLI::Inspect.reach([ep], "main.go", nil, false)
    rows.size.should eq(1)
    rows[0].via.map(&.to_text).should eq(["route@5", "route@apps/b/main.go:9", "callee:render@apps/b/main.go:12"])
    JSON.parse(rows[0].via[0].to_json)["path"]?.should be_nil
  end

  it "explains an empty reach differently for a seen file and an unseen name" do
    ep = endpoint("GET", "/x", "app/controllers/articles_controller.rb", 4)
    ep.push_callee(Callee.new("current_user", "app/controllers/application_controller.rb", 36))
    Noir::CLI::ReachCommand.empty_hint([ep], "application_controller.rb").should start_with("Noir recorded no route")
    Noir::CLI::ReachCommand.empty_hint([ep], "nothing.rb").should start_with("no recorded location ends with nothing.rb")
  end
end
