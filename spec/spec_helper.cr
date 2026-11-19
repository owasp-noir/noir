require "spec"
require "../src/config_initializer"
require "../src/utils/utils"

module Noir
  {% unless Noir.has_constant?("VERSION") %}
    VERSION = "SPEC"
  {% end %}
end

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

# Times the block with the collector kept out, for ratio (n vs 2n) guards: a
# collection tends to land in the larger run only, and on the Windows runner
# one costs about as much as the work being measured.
def measure_without_gc(&) : Time::Span
  GC.collect
  GC.disable
  begin
    Time.measure { yield }
  ensure
    GC.enable
  end
end
