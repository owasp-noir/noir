require "../../func_spec.cr"

# A throwaway Socket.IO server built inside `test/failover.test.js` is not
# inbound attack surface.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

socketio_endpoints = [build.call("ws://real event")]

FunctionalTester.new("fixtures/javascript/socketio_test_file/", {
  :techs     => 1,
  :endpoints => socketio_endpoints.size,
}, socketio_endpoints).perform_tests
