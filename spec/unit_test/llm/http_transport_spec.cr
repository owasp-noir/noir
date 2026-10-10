require "spec"
require "../../../src/llm/http_transport"

private def with_env(name : String, value : String?, &)
  prev = ENV[name]?
  if value
    ENV[name] = value
  else
    ENV.delete(name)
  end
  begin
    yield
  ensure
    if prev
      ENV[name] = prev
    else
      ENV.delete(name)
    end
  end
end

describe LLM::HttpTransport do
  describe ".timeout" do
    it "falls back to the default when unset" do
      with_env(LLM::HttpTransport::TIMEOUT_ENV, nil) do
        LLM::HttpTransport.timeout.should eq(LLM::HttpTransport::DEFAULT_TIMEOUT)
      end
    end

    it "honors a positive override in seconds" do
      with_env(LLM::HttpTransport::TIMEOUT_ENV, " 45 ") do
        LLM::HttpTransport.timeout.should eq(45.seconds)
      end
    end

    it "ignores values that would disable the bound" do
      ["0", "-1", "forever", ""].each do |raw|
        with_env(LLM::HttpTransport::TIMEOUT_ENV, raw) do
          LLM::HttpTransport.timeout.should eq(LLM::HttpTransport::DEFAULT_TIMEOUT)
        end
      end
    end
  end

  describe ".connect_timeout" do
    it "is separately tunable and short by default" do
      with_env(LLM::HttpTransport::CONNECT_TIMEOUT_ENV, nil) do
        LLM::HttpTransport.connect_timeout.should eq(LLM::HttpTransport::DEFAULT_CONNECT_TIMEOUT)
      end
      with_env(LLM::HttpTransport::CONNECT_TIMEOUT_ENV, "3") do
        LLM::HttpTransport.connect_timeout.should eq(3.seconds)
      end
    end
  end

  describe ".retryable_status?" do
    it "retries rate limits and transient gateway errors" do
      [408, 429, 500, 502, 503, 504].each do |code|
        LLM::HttpTransport.retryable_status?(code).should be_true
      end
    end

    it "does not retry configuration errors" do
      [400, 401, 403, 404, 422].each do |code|
        LLM::HttpTransport.retryable_status?(code).should be_false
      end
    end
  end

  describe ".loopback?" do
    it "keeps local providers quiet and flags remote hosts" do
      %w[localhost LOCALHOST app.localhost 127.0.0.1 127.8.9.1 ::1].each do |host|
        LLM::HttpTransport.loopback?(host).should be_true
      end
      %w[10.0.0.5 192.168.1.10 llm.internal example.com localhost.example.com].each do |host|
        LLM::HttpTransport.loopback?(host).should be_false
      end
    end
  end

  describe ".proxy_for" do
    it "picks the scheme's proxy variable, lowercase first" do
      with_env("https_proxy", nil) do
        with_env("HTTPS_PROXY", "proxy.corp:3128") do
          with_env("NO_PROXY", nil) do
            with_env("no_proxy", nil) do
              LLM::HttpTransport.proxy_for(URI.parse("https://api.openai.com/v1")).to_s.should eq("http://proxy.corp:3128")
              with_env("https_proxy", "http://lower:8080") do
                LLM::HttpTransport.proxy_for(URI.parse("https://api.openai.com/v1")).to_s.should eq("http://lower:8080")
              end
              with_env("http_proxy", nil) do
                with_env("HTTP_PROXY", nil) do
                  LLM::HttpTransport.proxy_for(URI.parse("http://llm.internal/v1")).should be_nil
                end
              end
            end
          end
        end
      end
    end

    it "goes direct for loopback and NO_PROXY hosts" do
      with_env("https_proxy", "http://proxy.corp:3128") do
        with_env("no_proxy", nil) do
          with_env("NO_PROXY", ".corp.example, *.internal,api.x.ai") do
            LLM::HttpTransport.proxy_for(URI.parse("https://localhost:8443")).should be_nil
            LLM::HttpTransport.proxy_for(URI.parse("https://llm.corp.example/v1")).should be_nil
            LLM::HttpTransport.proxy_for(URI.parse("https://a.b.internal/v1")).should be_nil
            LLM::HttpTransport.proxy_for(URI.parse("https://api.x.ai/v1")).should be_nil
            LLM::HttpTransport.proxy_for(URI.parse("https://api.openai.com/v1")).should_not be_nil
          end
          with_env("NO_PROXY", "*") do
            LLM::HttpTransport.proxy_for(URI.parse("https://api.openai.com/v1")).should be_nil
          end
        end
      end
    end
  end

  describe ".backoff" do
    it "grows exponentially from one second" do
      LLM::HttpTransport.backoff(1).should eq(1.second)
      LLM::HttpTransport.backoff(2).should eq(2.seconds)
      LLM::HttpTransport.backoff(3).should eq(4.seconds)
    end
  end

  describe ".retry_after" do
    it "uses the provider's hint when present" do
      response = HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => "5"})
      LLM::HttpTransport.retry_after(response).should eq(5.seconds)
    end

    it "clamps an unreasonable hint so a scan cannot be parked" do
      response = HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => "3600"})
      LLM::HttpTransport.retry_after(response).should eq(LLM::HttpTransport::MAX_RETRY_AFTER)
    end

    it "ignores a missing, unparsable or past hint" do
      LLM::HttpTransport.retry_after(nil).should be_nil
      ["soon", "Wed, 21 Oct 2015 07:28:00 GMT"].each do |raw|
        response = HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => raw})
        LLM::HttpTransport.retry_after(response).should be_nil
      end
    end

    it "reads an HTTP-date hint" do
      date = HTTP.format_time(Time.utc + 10.seconds)
      response = HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => date})
      span = LLM::HttpTransport.retry_after(response).not_nil!
      span.should be > 5.seconds
      span.should be <= 10.seconds
    end

    it "falls back to the backoff schedule" do
      LLM::HttpTransport.retry_delay(nil, 2).should eq(2.seconds)
    end
  end

  describe ".post_json_result" do
    it "does not retry a read timeout" do
      server = TCPServer.new("127.0.0.1", 0)
      accepted = 0
      spawn do
        while client = server.accept?
          accepted += 1
          spawn { sleep 2.seconds; client.close }
        end
      end
      with_env(LLM::HttpTransport::TIMEOUT_ENV, "0.2") do
        url = "http://127.0.0.1:#{server.local_address.port}/v1/chat/completions"
        LLM::HttpTransport.post_json_result(url, "{}", HTTP::Headers.new).should be_nil
      end
      accepted.should eq(1)
    ensure
      server.try &.close
    end
  end

  describe ".truncate_error_snippet" do
    it "caps oversized error bodies" do
      snippet = LLM::HttpTransport.truncate_error_snippet("x" * 5000)
      snippet.size.should eq(LLM::HttpTransport::MAX_ERROR_SNIPPET_SIZE + 3)
      snippet.ends_with?("...").should be_true
    end

    it "leaves short bodies alone" do
      LLM::HttpTransport.truncate_error_snippet("boom").should eq("boom")
    end

    it "masks a key the run has sent when the provider echoes it" do
      LLM::HttpTransport.remember_secret(HTTP::Headers{"Authorization" => "Bearer sk-test-KEY-1234"})
      snippet = LLM::HttpTransport.truncate_error_snippet(%({"error":{"message":"Incorrect API key provided: sk-test-KEY-1234"}}))
      snippet.should eq(%({"error":{"message":"Incorrect API key provided: ***"}}))
    end
  end
end
