require "../../spec_helper"
require "http/server"
require "../../../src/deliver/send_req"
require "../../../src/deliver/send_webhook"
require "../../../src/deliver/send_elasticsearch"
require "../../../src/models/endpoint"
require "../../../src/models/skipped_files"

# Delivery that never landed is coverage the user asked for and did not get.
#
# All three paths warned and moved on, which reads fine in a terminal and is
# invisible in CI: `--strict` looked only at analyzer failures, so a pipeline
# whose entire purpose is exporting the catalog to a SIEM exited 0 while
# exporting nothing. Every one of these repros exited 0 before the fix.
#
# Port 1 on loopback is closed on every platform the suite runs on, so the
# connection is refused immediately — no timeout, no network access.
private UNREACHABLE = "http://127.0.0.1:1"

private def deliver_gaps : Array(AnalyzerFailure)
  Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)
    .select { |failure| failure.tech == Noir::SkippedFiles::DELIVER_SCOPE }
end

describe "undelivered export reporting" do
  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  endpoints = [Endpoint.new("#{UNREACHABLE}/api", "GET")]

  it "records a webhook POST that never landed" do
    SendWebhook.new(create_test_options).run(endpoints, "#{UNREACHABLE}/hook")

    gaps = deliver_gaps
    gaps.size.should eq(1)
    gaps.first.message.should contain("webhook delivery")
    # Named by origin only: webhook URLs carry their token in the path, and
    # this message lands in the report's `errors` list.
    gaps.first.message.should contain("#{UNREACHABLE}/***")
    gaps.first.message.should_not contain("/hook")
  end

  it "records an Elasticsearch export that never landed" do
    SendElasticSearch.new(create_test_options).run(endpoints, UNREACHABLE)

    gaps = deliver_gaps
    gaps.size.should eq(1)
    gaps.first.message.should contain("Elasticsearch delivery")
  end

  it "records probes that could not be sent" do
    sender = SendReq.new(create_test_options)
    sender.run(endpoints)

    # The existing counter still says what it said; the point is that the
    # count now leaves the object and reaches `errors`.
    sender.undeliverable_count.should eq(1)

    gaps = deliver_gaps
    gaps.size.should eq(1)
    gaps.first.message.should contain("probe delivery: 1 request could not be sent")
  end

  # Crest followed the 307 as a body-less GET carrying the request headers,
  # so a `--probe-header` token reached whatever host `Location` named and
  # the catalog reached nobody, all while the export reported success.
  it "records a redirected export instead of following it to another host" do
    stolen = [] of String?
    other = HTTP::Server.new do |ctx|
      stolen << ctx.request.headers["Authorization"]?
      ctx.response.print "ok"
    end
    other_address = other.bind_tcp("127.0.0.1", 0)
    spawn { other.listen }

    redirector = HTTP::Server.new do |ctx|
      ctx.response.status_code = 307
      ctx.response.headers["Location"] = "http://127.0.0.1:#{other_address.port}/steal"
    end
    redirect_address = redirector.bind_tcp("127.0.0.1", 0)
    spawn { redirector.listen }
    Fiber.yield

    begin
      options = create_test_options
      options["probe_header"] = YAML::Any.new([YAML::Any.new("Authorization: Bearer SECRET")])
      SendWebhook.new(options).run(endpoints, "http://127.0.0.1:#{redirect_address.port}/hook")

      # `run` is synchronous, so a followed redirect has landed by now.
      stolen.should be_empty
      deliver_gaps.size.should eq(1)
      deliver_gaps.first.message.should contain("webhook delivery")
    ensure
      redirector.close
      other.close
    end
  end

  # A delivery that worked must leave no trace, or every successful export
  # would fail `--strict`.
  it "stays silent when there is nothing to deliver" do
    SendReq.new(create_test_options).run([] of Endpoint)

    deliver_gaps.should be_empty
  end
end
