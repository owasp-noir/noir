require "spec"
require "../src/config_initializer"

# Helper method to create default test options with common test settings.
# This method:
# - Creates default options from ConfigInitializer
# - Sets nolog=true to suppress log output during tests
#
# Usage:
#   options = create_test_options
#   options["base"] = YAML::Any.new([YAML::Any.new("path/to/test")])
def create_test_options : Hash(String, YAML::Any)
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["nolog"] = YAML::Any.new(true)
  options
end
