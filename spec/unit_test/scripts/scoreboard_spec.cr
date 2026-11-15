require "spec"
require "../../../scripts/scoreboard"

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
end
