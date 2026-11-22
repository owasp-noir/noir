require "spec"
require "../../../scripts/scoreboard"

# Small serialized scanner reports, including rows with multiple contributors.
private def scoreboard_row(url, techs, params = [] of {String, String}, tags = [] of {String, String},
                           method = "GET", protocol = "http", paths = [] of String)
  JSON.parse({
    protocol: protocol, method: method, url: url,
    details: {technologies: techs, code_paths: paths.map { |path| {path: path} }},
    params: params.map { |(type, name)| {param_type: type, name: name} },
    tags: tags.map { |(name, tagger)| {name: name, tagger: tagger} },
  }.to_json)
end

private def scoreboard_report(*rows, detected = [] of String)
  JSON.parse({scan_technologies: detected, endpoints: rows}.to_json)
end

describe Scoreboard do
  it "scores merged HTTP contributors and marks only code endpoints" do
    report = JSON.parse(<<-JSON)
      {"endpoints":[
      {"protocol":"http","details":{"technologies":["go_gin","oas3"]},"resolution":{"prefix":"unresolved","handler":"heuristic"}},
      {"protocol":"http","details":{"technologies":["oas2"]},"resolution":{"prefix":"unresolved"}},
      {"protocol":"http","details":{"technology":"go_gin","technologies":[]}},
      {"protocol":"http","details":{"technologies":["go_gin"]},"resolution":{"handler":"heuristic"}},
      {"protocol":"http","details":{"technologies":["nginx"]}},
      {"protocol":"websocket","details":{"technologies":["go_gin"]}}
      ]}
      JSON
    result = Scoreboard.score(report, "go_gin")
    result["matched"].as_i.should eq(1)
    result["spec_only"].as_i.should eq(1)
    result["code_only"].as_i.should eq(2)
    result["recall"].as_f.should eq(0.5)
    result["agreement"].as_f.should eq(1.0 / 3)
    result["marked"].as_i.should eq(2)
    result["marked_matched"].should eq(1)
    result["marked_code_only"].should eq(1)
    result["marked_share"].as_f.should eq(2.0 / 3)
    result["claims"]["handler:heuristic"]["count"].as_i.should eq(2)
    result["claims"]["prefix:unresolved"]["count"].as_i.should eq(1)
  end

  it "reports undefined ratios for empty denominators" do
    result = Scoreboard.score(JSON.parse(%({"endpoints":[]})), "go_gin")
    result["recall"].raw.should be_nil
    result["agreement"].raw.should be_nil
    result["marked_share"].raw.should be_nil
  end

  it "reads detectors independently of endpoint contributors and attributes HTTP deltas to the pin" do
    forced = scoreboard_report(scoreboard_row("/kept/:id", %w[go_gin oas3]),
      scoreboard_row("/lost", %w[go_gin]), scoreboard_row("/lost", %w[go_gin], method: "POST"),
      scoreboard_row("/doc", %w[oas3]), scoreboard_row("/socket", %w[go_gin], protocol: "ws"))
    automatic = scoreboard_report(scoreboard_row("/kept/{key}", %w[nginx go_gin oas3]),
      scoreboard_row("/lost", %w[nginx oas3]), scoreboard_row("/lost", %w[go_gin], method: "POST"),
      scoreboard_row("/new", %w[go_gin]), detected: %w[oas3 go_chi go_gin nginx])
    pins = %w[go_gin ruby_rails go_chi]
    delta = Scoreboard.detection_rows(forced, automatic, "go_gin")
    delta[:forced_only].map { |r| {r["method"].as_s, r["url"].as_s} }.should eq([{"GET", "/lost"}])
    delta[:automatic_only].map(&.["url"].as_s).should eq(["/new"])
    Scoreboard.detection(automatic, pins, "go_gin", delta).should eq(JSON.parse(
      %({"detected":true,"other_technologies":["nginx","oas3"],"forced_only":1,"automatic_only":1,"skipped":0})))
    %w[go_chi ruby_rails].each do |tech|
      empty_delta = Scoreboard.detection_rows(forced, automatic, tech)
      result = Scoreboard.detection(automatic, pins, tech, empty_delta)
      result["detected"].as_bool.should eq(tech == "go_chi")
      result["forced_only"].as_i.should eq(0)
      result["automatic_only"].as_i.should eq(0)
    end
  end

  it "compares independent parameter sets only on matched rows by location, header case and path slot" do
    forced = scoreboard_report(scoreboard_row("/org/:a/users/{b:[0-9]+}", %w[go_chi oas3], [{"query", "merged-only"}]),
      scoreboard_row("/only-in-code", %w[go_chi]))
    code = scoreboard_report(scoreboard_row("/org/:a/users/{b:[0-9]+}", %w[go_chi],
      [{"path", "a"}, {"header", "X-Key"}, {"header", "x-key"}, {"query", "Search"}, {"cookie", "sid"},
       {"header", "moved"}, {"path", "extra"}, {"json", "body"}, {"body", "field"}, {"form", "body"}, {"json", "Code"}]))
    document = scoreboard_report(scoreboard_row("/org/{org}/users/<int:user>", %w[oas3],
      [{"path", "user"}, {"path", "org"}, {"header", "x-key"}, {"query", "search"}, {"cookie", "sid"},
       {"query", "moved"}, {"query", "extra"}, {"form", "field"}, {"form", "body"}, {"json", "field2"}]))
    result = Scoreboard.matched_measurements(forced, code, document, "go_chi")
    result["params"].should eq(JSON.parse(%({"both":3,"spec_only":4,"code_only":3,"recall":#{3.0/7},"agreement":0.5})))
    result["body_fields"].should eq(JSON.parse(%({"both":2,"spec_only":1,"code_only":1,"recall":#{2.0/3},"agreement":#{2.0/3}})))
  end

  it "compares repeated path slots and name-first angle placeholders by position" do
    forced = scoreboard_report(scoreboard_row("/u/<owner:int>/x/<owner:int>", %w[python_sanic oas3]))
    code = scoreboard_report(scoreboard_row("/u/<owner:int>/x/<owner:int>", %w[python_sanic], [{"path", "owner"}]))
    document = scoreboard_report(scoreboard_row("/u/{a}/x/{b}", %w[oas3], [{"path", "b"}, {"path", "a"}]))
    Scoreboard.matched_measurements(forced, code, document, "python_sanic")["params"]["both"].should eq(2)
  end

  it "retains multiplicity and contributor scope when comparing detection rows" do
    row = scoreboard_row("/items", %w[go_gin], paths: ["one/item.go"])
    row["details"].as_h["origins"] = JSON.parse(%([{"technology":"go_gin","project":"one"}]))
    other = scoreboard_row("/items", %w[go_gin], paths: ["two/item.go"])
    other["details"].as_h["origins"] = JSON.parse(%([{"technology":"go_gin","project":"two"}]))
    delta = Scoreboard.detection_rows(scoreboard_report(row, row), scoreboard_report(row, other), "go_gin")
    delta[:forced_only].map(&.["locations"][0]["path"].as_s).should eq(["one/item.go"])
    delta[:automatic_only].map(&.["locations"][0]["path"].as_s).should eq(["two/item.go"])
  end

  it "uses merge locations when the optimizer kept distinct rows at the same address" do
    matched = scoreboard_row("/item/{id}", %w[oas2 java_spring], paths: ["one.java", "api.yaml"])
    code = scoreboard_report(scoreboard_row("/item/{id}", %w[java_spring], paths: ["two.java"]),
      scoreboard_row("/item/{id}", %w[java_spring], [{"query", "ticket"}], paths: ["one.java"]))
    spec = scoreboard_report(scoreboard_row("/item/{key}", %w[oas2], [{"query", "ticket"}]))
    Scoreboard.matched_measurements(scoreboard_report(matched), code, spec, "java_spring")["params"]["both"].should eq(1)
    expect_raises(Exception, /Cannot identify OpenAPI row/) do
      Scoreboard.matched_measurements(scoreboard_report(matched), code, scoreboard_report, "java_spring")
    end
  end

  it "counts all four guard outcomes from OAS access and framework auth tags" do
    # The importer emits auth for a required operation or inherited root
    # requirement, anonymous for [] or an optional {} alternative, and no tag
    # when neither level declares security. Merged rows lose OAS access tags.
    access = [{"auth", "oas2_access"}]
    auth = [{"auth", "go_auth"}]
    open = [{"anonymous", "oas3_access"}]
    urls = %w[/root /required /public /optional /unspecified]
    forced = JSON.parse({endpoints: urls.map { |url| scoreboard_row(url, %w[go_gin oas3]) }}.to_json)
    document = scoreboard_report(scoreboard_row("/root", %w[oas2], tags: access),
      scoreboard_row("/required", %w[oas3], tags: [{"auth", "oas3_access"}]),
      scoreboard_row("/public", %w[oas3], tags: open), scoreboard_row("/optional", %w[oas3], tags: open),
      scoreboard_row("/unspecified", %w[oas3]))
    code = scoreboard_report(scoreboard_row("/root", %w[go_gin], tags: auth),
      scoreboard_row("/required", %w[go_gin], tags: access), scoreboard_row("/public", %w[go_gin], tags: auth),
      scoreboard_row("/optional", %w[go_gin], tags: [{"authz", "go_auth"}]), scoreboard_row("/unspecified", %w[go_gin]))
    result = Scoreboard.matched_measurements(forced, code, document, "go_gin")
    result["guards"].should eq(JSON.parse(%({"both_guarded":1,"both_open":2,"spec_guarded_code_open":1,"spec_open_code_guarded":1})))
    %w[params body_fields].each do |key|
      result[key]["recall"].raw.should be_nil
      result[key]["agreement"].raw.should be_nil
    end
  end

  it "sums counts across repositories before dividing, including one-sided and empty sets" do
    forced = scoreboard_report(scoreboard_row("/items", %w[go_gin oas3]))
    code = scoreboard_report(scoreboard_row("/items", %w[go_gin], [{"json", "body"}, {"json", "code"}]))
    document = scoreboard_report(scoreboard_row("/items", %w[oas3], [{"query", "limit"}]))
    first = Scoreboard.matched_measurements(forced, code, document, "go_gin")
    first["params"]["recall"].should eq(0.0)
    first["params"]["agreement"].raw.should be_nil
    first["body_fields"]["agreement"].should eq(0.0)
    first["body_fields"]["recall"].raw.should be_nil
    code = scoreboard_report(scoreboard_row("/items", %w[go_gin], [{"query", "limit"}]))
    second = Scoreboard.matched_measurements(forced, code, document, "go_gin")
    first.as_h["detection"] = JSON.parse(%({"detected":true,"other_technologies":["nginx"],"forced_only":2,"automatic_only":1}))
    second.as_h["detection"] = JSON.parse(%({"detected":false,"other_technologies":["oas3","nginx"],"forced_only":1,"automatic_only":0}))
    totals = Scoreboard.measurement_totals([first, second])
    totals["params"].should eq(JSON.parse(%({"both":1,"spec_only":1,"code_only":0,"recall":0.5,"agreement":1.0})))
    totals["body_fields"]["recall"].raw.should be_nil
    totals["guards"]["both_open"].should eq(2)
    totals["detection"].should eq(JSON.parse(%({"detected_repositories":1,"other_technologies":["nginx","oas3"],"forced_only":3,"automatic_only":1})))
  end

  it "audits every small bucket and spreads 25 samples over repositories and sides" do
    rows = (0...80).map do |i|
      JSON.parse({repository: i < 3 ? "small" : "large", side: i.even? ? "spec-only" : "code-only", method: "GET", url: "/#{i}"}.to_json)
    end
    selected = Scoreboard.sample(rows)
    selected.size.should eq(25)
    selected.uniq.size.should eq(25)
    selected.count { |row| row["repository"].as_s == "small" }.should eq(3)
    selected.map(&.["side"].as_s).uniq!.size.should eq(2)
    Scoreboard.sample(rows.first(12)).size.should eq(12)
    Scoreboard.sample([] of JSON::Any).should be_empty
  end

  it "removes only an explicitly declared server prefix before Noir imports the spec" do
    doc = JSON.parse(%({"openapi":"3.0.3","servers":[{"url":"https://{project}.example/auth/v1"}],"paths":{"/token":{"post":{}}}}))
    Scoreboard.strip_spec_prefix!(doc, "/auth/v1")
    doc["servers"][0]["url"].as_s.should eq("https://{project}.example")
    doc["paths"].as_h.keys.should eq(["/token"])
  end

  it "rejects undeclared prefixes and scoped server overrides" do
    doc = JSON.parse(%({"openapi":"3.0.3","servers":[{"url":"https://example/auth/v10"}],"paths":{}}))
    expect_raises(Exception, /differs from declared server/) { Scoreboard.strip_spec_prefix!(doc, "/auth/v1") }
    doc = JSON.parse(%({"openapi":"3.0.3","servers":[{"url":"https://example/auth/v1"}],"paths":{"/token":{"post":{"servers":[{"url":"https://other"}]}}}}))
    expect_raises(Exception, /Scoped servers/) { Scoreboard.strip_spec_prefix!(doc, "/auth/v1") }
  end

  it "removes only an explicitly declared Swagger 2 deployment basePath" do
    doc = JSON.parse(%({"swagger":"2.0","basePath":"/flowable-rest/service","paths":{"/repository/deployments":{"get":{}}}}))
    expect_raises(Exception, /differs from declared basePath/) { Scoreboard.strip_spec_prefix!(doc, "/service") }
    Scoreboard.strip_spec_prefix!(doc, "/flowable-rest/service")
    doc["basePath"].as_s.should eq("/")
    doc["paths"].as_h.keys.should eq(["/repository/deployments"])
    doc = JSON.parse(%({"swagger":"2.0","paths":{}}))
    expect_raises(Exception, /differs from declared basePath/) { Scoreboard.strip_spec_prefix!(doc, "/service") }
  end

  it "includes service exclusions in the snapshot identity" do
    repo = JSON.parse(%({"name":"service","exclude_paths":["./install"],"note":"evidence"}))
    Scoreboard.pin(repo).keys.sort!.should eq(%w[exclude_paths name])
    Scoreboard.pin(repo)["exclude_paths"][0].as_s.should eq("./install")
  end

  it "counts files the automatic scan skipped without failing the measurement" do
    automatic = JSON.parse(%({"endpoints":[],"scan_technologies":["go_gin"],"errors":[{"tech":"detect","message":"skipped 1 file"}]}))
    delta = Scoreboard.detection_rows(automatic, automatic, "go_gin")
    Scoreboard.detection(automatic, ["go_gin"], "go_gin", delta)["skipped"].as_i.should eq(1)
  end

  it "reads the credentials a document declares through its security schemes" do
    oas3 = JSON.parse(%({"components":{"securitySchemes":{"bearer":{"type":"http","scheme":"bearer"},"key":{"type":"apiKey","in":"header","name":"X-API-Key"},"session":{"type":"apiKey","in":"cookie","name":"Access_Token"}}}}))
    oas2 = JSON.parse(%({"securityDefinitions":{"q":{"type":"apiKey","in":"query","name":"token"},"b":{"type":"basic"}}}))
    Scoreboard.credential_params([oas3, oas2]).should eq(Set{
      {"header", "authorization"}, {"header", "x-api-key"}, {"cookie", "Access_Token"}, {"query", "token"},
    })
    Scoreboard.credential_params([JSON.parse("{}")]).should be_empty
  end
end

private def audit_repo(name, matched, code, doc)
  JSON.parse({name: name, technology: "go_chi", commit: "a" * 40, matched: matched, code_only: code,
              spec_only: doc, marked_matched: 0, marked_code_only: 0}.to_json)
end

private def audit_row(side, url, repo = "one", marked = false)
  JSON.parse({repository: repo, method: "GET", side: side, url: url, marked: marked}.to_json)
end

private def audit_label(side, url, verdict, repo = "one", pin = "a" * 40)
  Scoreboard::Label.new(repo, "go_chi", pin, side, "GET", url, verdict)
end

describe "Scoreboard route audit" do
  it "weights each repository's decided share by its population and keeps incomplete coverage visible" do
    repos = [audit_repo("one", 10, 100, 6), audit_repo("two", 0, 2, 0)]
    code = "code-only"
    doc = "spec-only"
    rows = [audit_row(code, "/a", marked: true), audit_row(code, "/b"), audit_row(code, "/c"),
            audit_row(code, "/extra"), audit_row(code, "/a", "two", marked: true),
            audit_row(doc, "/x"), audit_row(doc, "/y"), audit_row(doc, "/z")]
    labels = [audit_label(code, "/a", "real"), audit_label(code, "/b", "false_positive"),
              audit_label(code, "/c", "cannot_tell"), audit_label(code, "/a", "wrong_address", "two"),
              audit_label(doc, "/x", "wrong_address"), audit_label(doc, "/y", "miss"), audit_label(doc, "/z", "covered")]
    audit = Scoreboard.audit_summary(repos, {"go_chi" => rows}, labels)
    audit["estimated_precision"].should eq(JSON.parse({value: 60.0 / 112, sample_size: 3, unlabelled: 1, cannot_tell: 1}.to_json))
    audit["estimated_recall"]["value"].as_f.should eq(10.0 / 14)
    audit["code_sample"]["labelled"].should eq(4)
    audit["code_sample"]["marked_by_verdict"].should eq(JSON.parse(%({"real":1,"false_positive":0,"wrong_address":1,"cannot_tell":0})))
    rows[3]["verdict"].raw.should be_nil
  end

  it "keeps stale pins, sides, methods, slash differences and ambiguous addresses out of the estimate" do
    code = "code-only"
    doc = "spec-only"
    rows = [audit_row(code, "/same"), audit_row(code, "/same"), audit_row(code, "/slash/"),
            audit_row(code, "/method"), audit_row(code, "/pin"), audit_row(code, "/side")]
    labels = [audit_label(code, "/same", "real"), audit_label(code, "/slash", "real"),
              Scoreboard::Label.new("one", "go_chi", "a" * 40, code, "POST", "/method", "real"),
              audit_label(code, "/pin", "real", pin: "b" * 40), audit_label(doc, "/side", "miss")]
    audit = Scoreboard.audit_summary([audit_repo("one", 5, 6, 0)], {"go_chi" => rows}, labels)
    audit["code_sample"]["stale"].should eq(4)
    audit["spec_sample"]["stale"].should eq(1)
    audit["estimated_precision"]["value"].raw.should be_nil
    audit["estimated_precision"]["unlabelled"].should eq(6)
    audit["estimated_recall"]["value"].should eq(1.0)
    empty = Scoreboard.audit_summary([audit_repo("two", 0, 0, 0)], {"go_chi" => rows}, labels)
    empty["estimated_recall"]["value"].raw.should be_nil
    empty["estimated_precision"]["value"].raw.should be_nil
  end

  it "rejects duplicate labels, invalid side verdicts and missing evidence" do
    header = %w[repository technology commit side method url verdict source evidence].join('\t') + "\n"
    row = ["one", "go_chi", "a" * 40, "spec-only", "GET", "/route", "miss", "app.go:4", "Registers the handler."].join('\t') + "\n"
    Scoreboard.read_labels(IO::Memory.new(header + row)).size.should eq(1)
    [row + row, row.sub("miss", "real"), row.sub("app.go:4", "app.go"), row.sub("Registers the handler.", "")].each do |invalid|
      expect_raises(Exception) { Scoreboard.read_labels(IO::Memory.new(header + invalid)) }
    end
  end
end
