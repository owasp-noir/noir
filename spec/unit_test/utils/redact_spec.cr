require "../../spec_helper"
require "../../../src/utils/redact"

private def any(value : String) : YAML::Any
  YAML::Any.new(value)
end

private def list(*values : String) : YAML::Any
  YAML::Any.new(values.map { |v| YAML::Any.new(v) }.to_a)
end

describe Noir::Redact do
  it "masks the whole ai_key, but leaves an unset one empty" do
    Noir::Redact.option("ai_key", any("SECRETKEY123")).should eq("***")
    Noir::Redact.option("ai_key", any("")).should eq("")
  end

  it "keeps header and cookie names but hides their values" do
    out = Noir::Redact.option("probe_header", list("Authorization: Bearer TOPSECRET", "X-Api-Key=k"))
    out.should eq(%(["Authorization: ***", "X-Api-Key=***"]))
    Noir::Redact.option("set_pvalue_cookie", list("session=abc")).should eq(%(["session=***"]))
    Noir::Redact.option("set_pvalue_header", list("X-Tok:abc")).should eq(%(["X-Tok:***"]))
  end

  it "leaves non-credential pvalue rules readable" do
    Noir::Redact.option("set_pvalue", list("id=1")).should eq(%(["id=1"]))
    Noir::Redact.option("set_pvalue_query", list("page=2")).should eq(%(["page=2"]))
  end

  it "hides the value of a malformed header with no separator" do
    Noir::Redact.named_value("Authorization Bearer xyz").should eq("Authorization ***")
    Noir::Redact.named_value("tok123").should eq("***")
    Noir::Redact.named_value(": xyz").should eq(": ***")
  end

  it "masks query values of a provider URL but keeps the names" do
    Noir::Redact.option("ai_provider", any("http://au:PROVPW@127.0.0.1:1/v1?key=PROVKEY&code=C&x")).should eq("http://***@127.0.0.1:1/v1?key=***&code=***&x")
    Noir::Redact.url("Server=https://gw.test/v1?key=K, Model=m").should eq("Server=https://gw.test/v1?key=***, Model=m")
    Noir::Redact.option("ai_provider", any("openai")).should eq("openai")
  end

  it "strips URL userinfo, including a raw @ in the password" do
    Noir::Redact.option("url", any("http://user:p@ss@x.com:8080/a?b=1")).should eq("http://***@x.com:8080/a?b=***")
    Noir::Redact.option("export_es", any("https://elastic:pw@[::1]:9200/idx")).should eq("https://***@[::1]:9200/idx")
    Noir::Redact.option("url", any("http://x.com/a@b")).should eq("http://x.com/a@b")
  end

  it "reduces a webhook URL to its origin" do
    Noir::Redact.option("export_webhook", any("https://hooks.slack.com/services/T0/B0/XYZ?x=1")).should eq("https://hooks.slack.com/***")
    Noir::Redact.option("export_webhook", any("https://hooks.example.com")).should eq("https://hooks.example.com")
  end

  it "passes ordinary options through unchanged" do
    Noir::Redact.option("format", any("json")).should eq("json")
    Noir::Redact.option("base", list("./app")).should eq(%(["./app"]))
    Noir::Redact.option("debug", YAML::Any.new(true)).should eq("true")
  end

  it "masks every occurrence of a secret in free text, but not tiny ones" do
    Noir::Redact.secret("key sk-abc123 again sk-abc123", ["sk-abc123"]).should eq("key *** again ***")
    Noir::Redact.secret("abc", ["ab", ""]).should eq("abc")
  end
end
