require "../../func_spec.cr"

# An HTTP-client import (node-fetch/axios) says nothing about whether a file
# is a test: a standalone Socket.IO service and a GraphQL Yoga BFF both call
# upstream APIs. Only the test suites beside them stay suppressed.
socketio_endpoint = Endpoint.new("ws://lookup user", "SEND", [] of Param)
socketio_endpoint.protocol = "ws"

FunctionalTester.new("fixtures/javascript/socketio_fetch_service/", {
  :techs     => 1,
  :endpoints => 1,
}, [socketio_endpoint]).perform_tests

FunctionalTester.new("fixtures/javascript/graphql_yoga_fetch_bff/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/graphql#Query.hello", "POST", [
    Param.new("graphql_query_hello", "", "json"),
  ]),
]).perform_tests
