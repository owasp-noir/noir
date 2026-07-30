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

    it "ignores a missing or non-numeric hint" do
      LLM::HttpTransport.retry_after(nil).should be_nil
      response = HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => "Wed, 21 Oct 2015 07:28:00 GMT"})
      LLM::HttpTransport.retry_after(response).should be_nil
    end

    it "falls back to the backoff schedule" do
      LLM::HttpTransport.retry_delay(nil, 2).should eq(2.seconds)
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
  end
end
