require "../../spec_helper"
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
    gaps.first.message.should contain("#{UNREACHABLE}/hook")
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

  # A delivery that worked must leave no trace, or every successful export
  # would fail `--strict`.
  it "stays silent when there is nothing to deliver" do
    SendReq.new(create_test_options).run([] of Endpoint)

    deliver_gaps.should be_empty
  end
end
