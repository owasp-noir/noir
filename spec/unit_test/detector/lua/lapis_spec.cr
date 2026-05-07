require "../../../spec_helper"
require "../../../../src/detector/detectors/lua/*"

describe "Detect Lua Lapis" do
  options = create_test_options
  instance = Detector::Lua::Lapis.new options

  it "rockspec_with_lapis_dependency" do
    content = <<-ROCK
      package = "x"
      dependencies = { "lua", "lapis" }
      ROCK
    instance.detect("x.rockspec", content).should be_true
  end

  it "config_lua_with_lapis_config" do
    instance.detect("config.lua", "local config = require(\"lapis.config\")").should be_true
  end

  it "lua_require_lapis" do
    instance.detect("app.lua", "local lapis = require(\"lapis\")").should be_true
  end

  it "lua_application_reference" do
    instance.detect("app.lua", "local app = lapis.Application()").should be_true
  end

  it "moonscript_extends_application" do
    instance.detect("app.moon", "class extends lapis.Application").should be_true
  end

  it "non_lapis_lua" do
    instance.detect("app.lua", "print('hi')").should be_false
  end

  it "non_lua_extension" do
    instance.detect("app.rb", "require 'lapis'").should be_false
  end
end
