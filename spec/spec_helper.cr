require "spec"
require "../src/config_initializer"

# Helper method to create default test options
def create_test_options : Hash(String, YAML::Any)
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["nolog"] = YAML::Any.new(true)
  options
end
