require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/tagger/tagger"

describe "Tagger" do
  it "lists regular and framework tagger names for validation" do
    NoirTaggers.available_tagger_names.should contain("hunt")
    NoirTaggers.available_tagger_names.should contain("django_auth")
    NoirTaggers.available_tagger_names.should contain("all")
  end

  it "detects unknown tagger names" do
    NoirTaggers.unknown_tagger_names("hunt,madeup,django_auth").should eq(["madeup"])
  end

  it "rejects unknown tagger names before running" do
    noir_options = create_test_options

    expect_raises(ArgumentError, /Unknown tagger/) do
      NoirTaggers.run_tagger([] of Endpoint, noir_options, "madeup")
    end
  end

  # `--fail-on auth-removed` adds `AUTH_ENTRIES` when `--use-taggers` names
  # none of them, and that list is read off the `_auth` key suffix. A tagger
  # that emits the auth tag under another key would silently fall out of
  # the gate, so pin the convention against the sources.
  it "names every framework tagger that emits the auth tag with an _auth key" do
    emitting = Dir.glob(File.join(File.expand_path("../../../src/tagger/framework_taggers", __DIR__), "**", "*.cr")).compact_map do |path|
      source = File.read(path)
      next unless source.matches?(/Tag\.new\("auth",/)
      source.match(/key: "([a-z_]+)"/).try(&.[1])
    end
    emitting.should_not be_empty
    emitting.sort.should eq(NoirTaggers::AUTH_ENTRIES.map(&.key).sort!)
  end

  # Framework taggers sharing a tech append to the same tag arrays. They
  # used to run one fiber each, so a blocking read let `rails_security` tag
  # before `ruby_auth` on some runs and after it on others.
  it "applies framework taggers in registry order every run" do
    dir = File.tempname("noir-tagger-order")
    Dir.mkdir_p(dir)
    begin
      paths = (0...40).map do |i|
        path = File.join(dir, "things#{i}_controller.rb")
        filler = (0...200).map { |k| "  # filler #{k}\n" }.join
        File.write(path, "class Things#{i}Controller < ApplicationController\n" \
                         "  before_action :authenticate_user!\n" \
                         "  protect_from_forgery with: :null_session\n" \
                         "#{filler}  def index\n    render json: []\n  end\nend\n")
        path
      end
      options = create_test_options
      options["base"] = YAML::Any.new(dir)

      30.times do
        endpoints = paths.map do |path|
          details = Details.new(PathInfo.new(path, 204))
          details.technology = "ruby_rails"
          Endpoint.new("/things", "GET", [] of Param, details)
        end
        NoirTaggers.run_tagger(endpoints, options, "rails_security,ruby_auth")
        endpoints.map(&.tags.map(&.name)).uniq!.should eq([["auth", "csrf-protection"]])
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "knows whether a --use-taggers list emits the auth tag" do
    NoirTaggers.auth_tagging?("hunt,cors").should be_false
    NoirTaggers.auth_tagging?("hunt, Django_Auth").should be_true
    NoirTaggers.auth_tagging?("all").should be_true
  end

  # `--use-taggers Hunt` and `--use-taggers HUNT` used to error
  # because the canonical names in `available_tagger_names` are
  # lowercase. Users naturally try title-case or upper-case; force
  # a case-insensitive match instead.
  it "accepts tagger names regardless of case" do
    NoirTaggers.unknown_tagger_names("HUNT,Cors,oAuth").should be_empty
    NoirTaggers.unknown_tagger_names("Hunt,Bogus").should eq(["Bogus"])
  end

  it "hunt_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("q", "", "query"),
        Param.new("query", "", "query"),
        Param.new("filter", "", "query"),
        Param.new("X-Forwarded-For", "", "header"),
      ]),
      Endpoint.new("/api/sign_ups", "POST", [
        Param.new("url", "", "cookie"),
        Param.new("command", "", "cookie"),
        Param.new("sort", "", "query"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "hunt")
    expected_endpoints.each do |endpoint|
      endpoint.params.each do |param|
        case param.name
        when "query"
          param.tags.should be_empty
        when "url"
          param.tags.empty?.should be_false
          param.tags.each do |tag|
            tag.name.should eq("ssrf")
          end
        when "sort"
          param.tags.empty?.should be_false
          param.tags.each do |tag|
            tag.name.should eq("sqli")
          end
        end
      end
    end
  end

  it "oauth_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/token", "GET", [
        Param.new("client_id", "", "query"),
        Param.new("grant_type", "", "query"),
        Param.new("code", "", "query"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "oauth")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("oauth")
      end
    end
  end

  it "cors_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("q", "", "query"),
        Param.new("Origin", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "cors")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("cors")
      end
    end
  end

  it "soap_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("SOAPAction", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "soap")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("soap")
      end
    end
  end

  it "websocket_tagger_1" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/ws", "GET", [
        Param.new("sec-websocket-version", "", "header"),
        Param.new("Sec-WebSocket-Key", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "websocket")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end

  it "websocket_tagger_2" do
    noir_options = create_test_options
    e = Endpoint.new("/ws", "GET")
    e.protocol = "ws"

    expected_endpoints = [e]

    NoirTaggers.run_tagger(expected_endpoints, noir_options, "websocket")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end

  it "graphql_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/graphql", "POST", [
        Param.new("query", "{ users { id } }", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "graphql")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("graphql")
      end
    end
  end

  it "mcp_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/mcp", "POST"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "mcp")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("mcp")
      end
    end
  end

  it "jwt_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/auth/token", "POST", [
        Param.new("token", "", "form"),
        Param.new("refresh_token", "", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "jwt")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("jwt")
      end
    end
  end

  it "file_upload_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/upload", "POST", [
        Param.new("file", "", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "file_upload")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("file_upload")
      end
    end
  end

  it "pii_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/kyc", "POST", [
        Param.new("ssn", "", "json"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "pii")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("pii")
      end
    end
  end

  it "admin_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/admin/users", "GET"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "admin")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("admin")
      end
    end
  end

  it "payment_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/checkout", "POST"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "payment")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("payment")
      end
    end
  end

  it "webhook_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/webhooks/stripe", "POST"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "webhook")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("webhook")
      end
    end
  end

  it "crypto_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/encrypt", "POST"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "crypto")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("crypto")
      end
    end
  end

  it "debug_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/actuator/env", "GET"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "debug")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("debug")
      end
    end
  end

  it "api_docs_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/swagger-ui.html", "GET"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "api_docs")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("api_docs")
      end
    end
  end

  it "account_recovery_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/auth/forgot-password", "POST"),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "account_recovery")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("account_recovery")
      end
    end
  end
end
