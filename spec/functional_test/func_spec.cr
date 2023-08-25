require "./func_model.cr"

# Initializes a FunctionalTester instance.
# @param path [String] The directory path where test data is located. (like fixtures/kemal/)
# @param expected_count [Hash(Symbol, Int32)] Defines the expected data counts in the test.
#   - :techs
#   - :endpoints
#   - :params

tester_kemal = FunctionalTester.new("fixtures/kemal/", {
    :techs => 1,
    :endpoints => 2
}).test_all