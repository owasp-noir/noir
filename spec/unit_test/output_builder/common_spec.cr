require "../../spec_helper"
require "../../../src/output_builder/common"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderCommon" do
  it "should not display tech by default" do
    options = {
      "debug"         => YAML::Any.new(false),
      "verbose"       => YAML::Any.new(false),
      "color"         => YAML::Any.new(false),
      "nolog"         => YAML::Any.new(false),
      "output"        => YAML::Any.new(""),
      "include_techs" => YAML::Any.new(false),
      "include_path"  => YAML::Any.new(false),
      "status_codes"  => YAML::Any.new(false),
      "exclude_codes" => YAML::Any.new(""),
    }
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.details.technology = "scala_akka"
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Tech should not be displayed when include_techs is false
    output.should_not contain("tech:")
    output.should_not contain("scala_akka")
  end

  it "should display tech when include_techs flag is set" do
    options = {
      "debug"         => YAML::Any.new(false),
      "verbose"       => YAML::Any.new(false),
      "color"         => YAML::Any.new(false),
      "nolog"         => YAML::Any.new(false),
      "output"        => YAML::Any.new(""),
      "include_techs" => YAML::Any.new(true),
      "include_path"  => YAML::Any.new(false),
      "status_codes"  => YAML::Any.new(false),
      "exclude_codes" => YAML::Any.new(""),
    }
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.details.technology = "scala_akka"
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Tech should be displayed when include_techs is true
    output.should contain("tech:")
    output.should contain("scala_akka")
  end

  it "should not display tech line when technology is nil" do
    options = {
      "debug"         => YAML::Any.new(false),
      "verbose"       => YAML::Any.new(false),
      "color"         => YAML::Any.new(false),
      "nolog"         => YAML::Any.new(false),
      "output"        => YAML::Any.new(""),
      "include_techs" => YAML::Any.new(true),
      "include_path"  => YAML::Any.new(false),
      "status_codes"  => YAML::Any.new(false),
      "exclude_codes" => YAML::Any.new(""),
    }
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    # Don't set technology (it should be nil)
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Tech should not be displayed when technology is nil, even if flag is set
    output.should_not contain("tech:")
  end

  it "should work correctly with both include_path and include_techs" do
    options = {
      "debug"         => YAML::Any.new(false),
      "verbose"       => YAML::Any.new(false),
      "color"         => YAML::Any.new(false),
      "nolog"         => YAML::Any.new(false),
      "output"        => YAML::Any.new(""),
      "include_path"  => YAML::Any.new(true),
      "include_techs" => YAML::Any.new(true),
      "status_codes"  => YAML::Any.new(false),
      "exclude_codes" => YAML::Any.new(""),
    }
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.details.technology = "python_flask"
    endpoint.details.add_path(PathInfo.new("/app/test.py", 42))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Both tech and file path should be displayed
    output.should contain("tech:")
    output.should contain("python_flask")
    output.should contain("file:")
    output.should contain("/app/test.py")
    output.should contain("line 42")
  end
end
