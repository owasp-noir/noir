require "../../spec_helper"
require "file_utils"
require "http/server"
require "json"

# The AI analyzer driven end to end: the built `bin/noir` against an
# in-process OpenAI-compatible server that records every request body.
# The unit specs cover the clients and the analyzer one piece at a time;
# what slipped past them (secret files in a payload, the optimizer
# rewriting a static route, a bad key repeated for every file) only shows
# up across the whole CLI run.
private REPO_ROOT = File.expand_path(File.join(__DIR__, "..", "..", ".."))
private BINARY    = File.join(REPO_ROOT, "bin", {% if flag?(:windows) %} "noir.exe" {% else %} "noir" {% end %})

private SECRET = "NOIR_E2E_SECRET_VALUE"

# The reply for each kind of request, told apart by the schema name the
# client sends in `response_format`. `/api/USERS/*` is a static Sinatra
# route; `/api/ORDERS/*` is only in a comment, so the AI analyzer alone
# reports it and the optimizer may respell its wildcard.
private def fake_reply(body : String) : String
  content = if body.includes?("filter_files")
              # Empty, so the analyzer falls back to every source file.
              %({"files": []})
            elsif body.includes?("optimize_endpoint")
              url = body[/URL: (\S+?)\\n/, 1]? || "/"
              {optimized_url: url.sub("*", "{rest}"), optimized_params: [] of String}.to_json
            else
              {endpoints: ["/api/USERS/*", "/api/ORDERS/*"].map { |url| {url: url, method: "GET", params: [] of String} }}.to_json
            end
  {choices: [{message: {role: "assistant", content: content}, finish_reason: "stop"}]}.to_json
end

private class FakeProvider
  getter bodies = [] of String
  property status = 200

  def initialize
    @server = HTTP::Server.new do |ctx|
      body = ctx.request.body.try(&.gets_to_end) || ""
      @bodies << body
      ctx.response.status_code = @status
      ctx.response.content_type = "application/json"
      ctx.response.print(@status == 200 ? fake_reply(body) : %({"error": {"message": "invalid api key"}}))
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
  end

  def url : String
    "http://127.0.0.1:#{@address.port}/v1"
  end

  def close
    @server.close
  end
end

private record CliRun, stdout : String, stderr : String, exit_code : Int32

private def binary_ready? : Bool
  return false unless File.exists?(BINARY)
  built_at = File.info(BINARY).modification_time
  Dir.glob(File.join(REPO_ROOT, "src", "**", "*.cr")).none? do |source|
    File.info(source).modification_time > built_at
  end
end

# A Sinatra app with more than ten files, so the FILTER request (which
# lists every path) is sent too, next to two credentials files.
private def write_project(dir : String)
  Dir.mkdir_p(File.join(dir, "lib"))
  File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\ngem 'sinatra'\n")
  File.write(File.join(dir, "app.rb"), <<-RUBY)
    require 'sinatra'

    # The mobile client also calls /api/ORDERS/*, served by the gateway.
    get '/api/USERS/*' do
      'ok'
    end
    RUBY
  10.times { |i| File.write(File.join(dir, "lib", "helper#{i}.rb"), "module Helper#{i}\nend\n") }
  File.write(File.join(dir, ".env"), "API_TOKEN=#{SECRET}\n")
  File.write(File.join(dir, "id_rsa"), "-----BEGIN OPENSSH PRIVATE KEY-----\n#{SECRET}\n")
end

private def run_scan(dir : String, provider : FakeProvider, extra : Array(String) = [] of String) : CliRun
  home = File.join(dir, ".noir-home")
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  args = ["scan", "-b", File.join(dir, "project"), "-f", "json",
          "--ai-provider", provider.url, "--ai-model", "fake-model", "--ai-key", "test-key",
          # One file per bundle and one request at a time, so the request
          # count below is deterministic.
          "--ai-max-token", "700", "--concurrency", "1"] + extra
  env = {"NOIR_HOME" => home, "NOIR_CACHE_DISABLE" => "1", "NOIR_AI_KEY" => nil}
  status = Process.run(BINARY, args: args, env: env, output: stdout, error: stderr)
  CliRun.new(stdout: stdout.to_s, stderr: stderr.to_s, exit_code: status.exit_code)
end

private def with_project(&)
  dir = File.join(Dir.tempdir, "noir-ai-e2e-#{Random.new.hex(4)}")
  write_project(File.join(dir, "project"))
  provider = FakeProvider.new
  begin
    yield dir, provider
  ensure
    provider.close
    FileUtils.rm_rf(dir)
  end
end

describe "AI analyzer against a fake provider (built binary)" do
  unless binary_ready?
    pending "needs an up-to-date bin/noir — run `shards build` to exercise these"
    next
  end

  it "never sends credentials files and leaves static routes to the optimizer alone" do
    with_project do |dir, provider|
      result = run_scan(dir, provider)
      result.exit_code.should eq(0)

      provider.bodies.should_not be_empty
      provider.bodies.any?(&.includes?("filter_files")).should be_true
      provider.bodies.each do |body|
        body.should_not contain(SECRET)
        # As a path in the FILTER list or a bundle label, not prompt prose.
        body.should_not match(/[\\\/"](?:\.env|id_rsa)\b/)
      end

      urls = JSON.parse(result.stdout)["endpoints"].as_a.map(&.["url"].as_s)
      # The fake answered every optimize request with a respelled wildcard.
      # The AI-only route takes it; the static one is never even offered.
      urls.should contain("/api/USERS/*")
      urls.should contain("/api/ORDERS/{rest}")
      provider.bodies.none? { |body| body.includes?("optimize_endpoint") && body.includes?("USERS") }.should be_true
    end
  end

  it "stops after three auth failures and fails --strict with the files in errors" do
    with_project do |dir, provider|
      provider.status = 401
      result = run_scan(dir, provider, ["--strict"])

      # FILTER plus two bundles, then the cutoff; the rest are never sent.
      provider.bodies.size.should eq(3)
      result.stderr.should contain("failed its first 3 requests")
      result.exit_code.should eq(2)
      errors = JSON.parse(result.stdout)["errors"].to_json
      errors.should contain("skipped 12 files")
      errors.should contain("app.rb")
    end
  end

  it "sends nothing under --ai-dry-run" do
    with_project do |dir, provider|
      result = run_scan(dir, provider, ["--ai-dry-run"])
      result.exit_code.should eq(0)
      provider.bodies.should be_empty
      result.stderr.should contain("nothing was sent")
    end
  end
end
