require "../../func_spec.cr"

# `=begin`/`=end` blocks, heredoc bodies and anything after `__END__` are
# never run, so route-shaped text in them is not a route.
FunctionalTester.new("fixtures/ruby/sinatra_non_code/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/after-comment", "POST"),
]).perform_tests

FunctionalTester.new("fixtures/ruby/rails_non_code/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/after", "POST"),
]).perform_tests
