require "../../func_spec.cr"

# A connection callback that hands its socket to a handler function
# (`chatHandler(socket)`, defined in another module) registers that
# function's events too. The connection module imports nothing from
# `socket.io` (its `io` comes from ./app). A `ws` server that hands its
# socket to the same function adds nothing, nor does a node:net server.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

delegated_endpoints = [
  build.call("ws://ping me"),
  build.call("ws://send"),
  build.call("ws://chat_join"),
  # A prefix that is no string constant here keeps its name as a placeholder.
  build.call("ws://{otherPrefix}leave"),
  build.call("ws://history"),
  build.call("ws://kick"),
  build.call("ws://open"),
  # The prefix declared in the enclosing function, not another function's;
  # a reassigned `let` is not guessed.
  build.call("ws://inner_evt"),
  build.call("ws://{shifting}first"),
] + %w[after_write public_branch unbraced_if nested_check setting_check not_a_session
  function_style one_line_try write_in_try shuffled_args
  log_first awaited_read_first awaited_write_first chained_declaration call_in_shuffle
  helper_logs helper_rethrows helper_logged probe_port
  fetch_post raw_query builder_delete sync_write log_with_write decrement].map { |name| build.call("ws://#{name}") }

delegated_tester = FunctionalTester.new("fixtures/javascript/socketio_delegated/", {
  :techs     => 1,
  :endpoints => delegated_endpoints.size,
}, delegated_endpoints)
delegated_tester.perform_tests

it "skips the ws server's and the net server's events", tags: "functional" do
  urls = delegated_tester.app.endpoints.map(&.url)
  urls.should_not contain("ws://raw message")
  urls.should_not contain("ws://data")
  urls.should_not contain("ws://other_evt")
end

it "reports a delegated event at its own line", tags: "functional" do
  send = delegated_tester.app.endpoints.find! { |ep| ep.url == "ws://send" }
  send.details.code_paths.first.path.should end_with("handlers/chat.js")
  send.details.code_paths.first.line.should eq(9)
end
