require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/ruby/rails"

# `controller_to_endpoint` must not build its return value in `@result`.
#
# It used to open with `@result = [] of Endpoint`, i.e. it wiped the
# analyzer's accumulated endpoints and handed back its own fresh array. Its
# one caller compensated with `@result += controller_to_endpoint(...)`, which
# is correct only because Crystal evaluates the `+` receiver before the
# argument: the old array is read, then the call replaces `@result`, then the
# sum is assigned back.
#
# That made an ordinary-looking edit destructive. Rewriting the call site as
# `@result.concat(...)` — the form anyone would reach for, and the one that
# avoids an intermediate array — discarded every endpoint collected so far,
# silently. This example pins the method to a local so the caller is free to
# use either form.
describe "Analyzer::Ruby::Rails#controller_to_endpoint" do
  it "leaves already-collected endpoints alone" do
    options = create_test_options
    analyzer = Analyzer::Ruby::Rails.new(options)

    analyzer.result << Endpoint.new("/collected-earlier", "GET")

    # A path no file backs: the method returns early, which is the shortest
    # route to the assignment that used to do the damage.
    returned = analyzer.controller_to_endpoint("/nonexistent/controller.rb", "", "widgets")

    returned.should be_empty
    analyzer.result.map(&.url).should eq(["/collected-earlier"])
  end
end
