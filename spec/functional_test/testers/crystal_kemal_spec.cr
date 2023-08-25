require "../func_spec.cr"

# Initializes a FunctionalTester instance.
# @param path [String] The directory path where test data is located. (like fixtures/kemal/)
# @param expected_count [Hash(Symbol, Int32)] Defines the expected data counts in the test.
#   - :techs
#   - :endpoints

extected_endpoints = [
    Endpoint.new("/", "GET"),
    Endpoint.new("/socket", "GET"),
    Endpoint.new("/query", "POST", [Param.new("query", "", "body")]),
]

tester_kemal = FunctionalTester.new("fixtures/kemal/", {
    :techs => 1,
    :endpoints => 3
}, extected_endpoints).test_all