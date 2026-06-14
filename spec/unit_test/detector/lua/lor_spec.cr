require "../../../spec_helper"
require "../../../../src/detector/detectors/lua/*"

describe "Detect Lua lor" do
  options = create_test_options
  instance = Detector::Lua::Lor.new options

  it "rockspec_with_lor_dependency" do
    content = <<-ROCK
      package = "x"
      dependencies = { "lua", "lor" }
      ROCK
    instance.detect("x.rockspec", content).should be_true
  end

  it "lua_require_lor_index" do
    instance.detect("app.lua", "local lor = require(\"lor.index\")").should be_true
  end

  it "lua_require_lor_lib" do
    instance.detect("main.lua", "local s = require('lor.lib.middleware.session')").should be_true
  end

  it "lua_router_construction" do
    instance.detect("routes.lua", "local r = lor:Router()").should be_true
  end

  it "lua_app_construction" do
    instance.detect("main.lua", "local app = lor()").should be_true
  end

  it "non_lor_lua" do
    instance.detect("app.lua", "print('hi')").should be_false
  end

  it "color_word_not_matched" do
    instance.detect("app.lua", "local color = require('palette')").should be_false
  end

  it "lapis_not_matched_as_lor" do
    instance.detect("app.lua", "local app = lapis.Application()").should be_false
  end

  it "non_lua_extension" do
    instance.detect("app.rb", "require 'lor'").should be_false
  end
end
