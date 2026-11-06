require "../../spec_helper"
require "../../../src/utils/endpoint_filter"
require "../../../src/cli_validation"

private def ep(method : String, url : String, protocol : String = "http", tech : String = "python_flask") : Endpoint
  details = Details.new
  details.technology = tech
  endpoint = Endpoint.new(url, method, details)
  endpoint.protocol = protocol
  endpoint
end

private def terms(*texts : String) : Array(Noir::EndpointFilter::Term)
  texts.map { |t| Noir::EndpointFilter.parse_term(t) }.to_a
end

private def urls(endpoints : Array(Endpoint)) : Array(String)
  endpoints.map { |e| "#{e.method} #{e.url}" }
end

private def sample : Array(Endpoint)
  [
    ep("GET", "/api/users"),
    ep("POST", "/api/internal/sync"),
    ep("GET", "/admin"),
    ep("GET", "/administrator/login"),
    ep("GET", "/health"),
    ep("POST", "/health"),
    ep("CLI", "cli://tool/serve", "cli", "python_cli"),
  ]
end

describe Noir::EndpointFilter do
  describe ".parse_term" do
    it "reads a bare /path as a url pattern" do
      Noir::EndpointFilter.parse_term("/admin*").filters.url.should eq("/admin*")
    end

    it "reads key:value items, comma lists as OR and spaces as AND" do
      filters = Noir::EndpointFilter.parse_term("method:get,post url:/a,b tech:python_flask").filters
      filters.methods.should eq(%w[GET POST])
      # A URL can hold a comma, so it is one pattern, as in `noir query --url`.
      filters.url.should eq("/a,b")
      filters.techs.should eq(%w[python_flask])
    end

    it "splits only on the first colon" do
      Noir::EndpointFilter.parse_term("url:/users/:id").filters.url.should eq("/users/:id")
      Noir::EndpointFilter.parse_term("/users/:id").filters.url.should eq("/users/:id")
    end

    it "points the #3471 probe-filter shape at the keys that mean it" do
      expect_raises(Noir::EndpointFilter::TermError, /unknown key "CLI"; did you mean method:CLI or protocol:cli\?/) do
        Noir::EndpointFilter.parse_term("CLI:/*")
      end
      expect_raises(Noir::EndpointFilter::TermError, /did you mean method:GET\?/) do
        Noir::EndpointFilter.parse_term("GET:/admin")
      end
    end

    it "rejects keys whose data only exists after tagging and AI context" do
      %w[tag:auth sink:sql guard:x signal:ssrf].each do |text|
        expect_raises(Noir::EndpointFilter::TermError, /noir query --/) do
          Noir::EndpointFilter.parse_term(text)
        end
      end
    end

    it "rejects empty values, bare words and a key given twice" do
      ["", "   ", "url:", "method:,", "admin", "method:GET method:POST"].each do |text|
        expect_raises(Noir::EndpointFilter::TermError) do
          Noir::EndpointFilter.parse_term(text)
        end
      end
    end
  end

  describe ".apply" do
    it "drops every CLI endpoint by protocol" do
      kept, warnings = Noir::EndpointFilter.apply(sample, [] of Noir::EndpointFilter::Term, terms("protocol:cli"))
      kept.none?(&.cli?).should be_true
      kept.size.should eq(6)
      warnings.should be_empty
    end

    it "uses the query pattern rules: a glob is anchored, a plain value is a substring" do
      kept, _ = Noir::EndpointFilter.apply(sample, [] of Noir::EndpointFilter::Term, terms("/admin"))
      # Substring: `/admin` also takes `/administrator/login`.
      urls(kept).should_not contain("GET /administrator/login")
      kept, _ = Noir::EndpointFilter.apply(sample, [] of Noir::EndpointFilter::Term, terms("/api/*"))
      urls(kept).should eq(["GET /admin", "GET /administrator/login", "GET /health", "POST /health", "CLI cli://tool/serve"])
    end

    it "keeps any only-term match, then drops exclude matches" do
      kept, _ = Noir::EndpointFilter.apply(sample, terms("/api/*", "/health"), terms("/api/internal/*", "method:POST url:/health"))
      urls(kept).should eq(["GET /api/users", "GET /health"])
    end

    it "warns about a term that matched nothing, with the values that exist" do
      _, warnings = Noir::EndpointFilter.apply(sample, [] of Noir::EndpointFilter::Term, terms("protocol:clii", "/admn*"))
      messages = warnings.map(&.message)
      messages.should contain(%(--exclude-endpoints "protocol:clii" matched no endpoint (no endpoint carries protocol clii; in this report: cli, http)))
      messages.should contain(%(--exclude-endpoints "/admn*" matched no endpoint))
    end

    it "excludes a method exactly, but lets only-terms keep ANY routes as query does" do
      endpoints = [ep("GET", "/a"), ep("OPTIONS", "/a"), ep("ANY", "/:controller/:action")]
      kept, _ = Noir::EndpointFilter.apply(endpoints, [] of Noir::EndpointFilter::Term, terms("method:OPTIONS,HEAD"))
      urls(kept).should eq(["GET /a", "ANY /:controller/:action"])
      kept, _ = Noir::EndpointFilter.apply(endpoints, terms("method:GET"), [] of Noir::EndpointFilter::Term)
      urls(kept).should eq(["GET /a", "ANY /:controller/:action"])
    end

    it "matches a /-rooted pattern against the path of a -u joined URL, as on a --from report" do
      endpoints = [ep("GET", "https://t.example/sign"), ep("GET", "https://t.example/other"), ep("CLI", "cli://tool/sign", "cli", "python_cli")]
      kept, warnings = Noir::EndpointFilter.apply(endpoints, terms("/sign*"), [] of Noir::EndpointFilter::Term)
      urls(kept).should eq(["GET https://t.example/sign"])
      warnings.should be_empty
      Noir::EndpointFilter.url_matches?("/", "https://t.example").should be_true
      Noir::EndpointFilter.url_matches?("https://t.example/s*", "https://t.example/sign").should be_true
    end

    it "warns when nothing is left" do
      _, warnings = Noir::EndpointFilter.apply(sample, [] of Noir::EndpointFilter::Term, terms("/*", "protocol:cli"))
      warnings.map(&.message).should contain("--only-endpoints / --exclude-endpoints left none of the 7 endpoints")
    end
  end

  describe ".merged_warnings" do
    it "keeps a no-match warning in a diff only when neither side matched" do
      only = [] of Noir::EndpointFilter::Term
      # The new side has no CLI left; the old side had one.
      _, new_side = Noir::EndpointFilter.apply([ep("GET", "/a")], only, terms("protocol:cli", "/typo"))
      _, old_side = Noir::EndpointFilter.apply([ep("CLI", "cli://t", "cli")], only, terms("protocol:cli", "/typo"))
      merged = Noir::EndpointFilter.merged_warnings(new_side, old_side)
      merged.size.should eq(1)
      merged.first.should contain(%("/typo"))
    end

    it "keeps 'left none' in a diff only when both sides were emptied" do
      none = [] of Noir::EndpointFilter::Term
      _, new_side = Noir::EndpointFilter.apply([ep("GET", "/a")], terms("protocol:cli"), none)
      _, old_side = Noir::EndpointFilter.apply([ep("CLI", "cli://t", "cli")], terms("protocol:cli"), none)
      Noir::EndpointFilter.merged_warnings(new_side, old_side).should be_empty
      _, old_empty = Noir::EndpointFilter.apply([ep("GET", "/b")], terms("protocol:cli"), none)
      Noir::EndpointFilter.merged_warnings(new_side, old_empty).size.should eq(2)
    end
  end

  describe ".terms" do
    it "reads a YAML list or a single string, and nothing from an empty value" do
      list = YAML::Any.new([YAML::Any.new("protocol:cli"), YAML::Any.new("/admin*")])
      Noir::EndpointFilter.terms(list).map(&.text).should eq(["protocol:cli", "/admin*"])
      Noir::EndpointFilter.terms(YAML::Any.new("/x")).map(&.text).should eq(["/x"])
      Noir::EndpointFilter.terms(YAML::Any.new("")).should be_empty
      Noir::EndpointFilter.terms(nil).should be_empty
    end
  end
end

describe "Noir::CliValidation.validate_endpoint_filters!" do
  it "names the flag and the bad term before the scan starts" do
    options = {"exclude_endpoints" => YAML::Any.new([YAML::Any.new("CLI:/*")])}
    expect_raises(Noir::CliValidation::Error, /--exclude-endpoints "CLI:\/\*": unknown key "CLI"/) do
      Noir::CliValidation.validate_endpoint_filters!(options)
    end
  end

  it "accepts valid terms" do
    options = {
      "only_endpoints"    => YAML::Any.new([YAML::Any.new("/api/*")]),
      "exclude_endpoints" => YAML::Any.new([YAML::Any.new("protocol:cli,ws")]),
    }
    Noir::CliValidation.validate_endpoint_filters!(options)
  end
end
