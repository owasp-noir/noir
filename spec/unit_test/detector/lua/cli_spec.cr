require "../../../spec_helper"
require "../../../../src/detector/detectors/lua/*"

describe "Detect Lua CLI" do
  options = create_test_options
  instance = Detector::Lua::Cli.new options

  it "argparse_require" do
    instance.detect("tool.lua", "local argparse = require \"argparse\"").should be_true
  end

  it "argparse_call" do
    instance.detect("tool.lua", "local parser = argparse(\"tool\", \"A tool\")").should be_true
  end

  it "cliargs_require" do
    instance.detect("tool.lua", "local cli = require('cliargs')").should be_true
  end

  it "bare_global_arg_index" do
    instance.detect("script.lua", "local port = tonumber(arg[1])").should be_true
  end

  it "arg_index_after_concat" do
    instance.detect("script.lua", "print(\"usage: \"..arg[0])").should be_true
  end

  # OpenResty body-filter code reads the chunk and eof flag from `ngx.arg`;
  # a tree with only those is a web plugin, not a command-line program.
  it "ngx_arg_is_not_argv" do
    content = <<-LUA
      local chunk, eof = ngx.arg[1], ngx.arg[2]
      ngx.arg[1] = string.upper(chunk)
      LUA
    instance.detect("body_filter.lua", content).should be_false
  end

  it "field_arg_is_not_argv" do
    instance.detect("plugin.lua", "local v = ctx.arg[1]").should be_false
  end

  it "identifier_ending_in_arg_is_not_argv" do
    instance.detect("plugin.lua", "local v = myarg[1]").should be_false
  end

  it "non_cli_lua" do
    instance.detect("app.lua", "print('hi')").should be_false
  end

  it "non_lua_extension" do
    instance.detect("tool.rb", "local argparse = require 'argparse'").should be_false
  end
end
