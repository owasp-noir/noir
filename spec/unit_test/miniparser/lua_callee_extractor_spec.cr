require "spec"
require "../../../src/miniparsers/lua_callee_extractor"

describe Noir::LuaCalleeExtractor do
  it "extracts Lua receiver, method, bare, and command-style callees" do
    body = <<-LUA
      local users = UserService:list(self.params.page)
      Audit.write("users")
      render_json(users)
      ngx.say "ok"
      local ignored = "Fake.call()"
      -- Commented.call()
      print("debug")
      LUA

    callees = Noir::LuaCalleeExtractor.callees_for_body(body, "app.lua", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.list", 10},
      {"Audit.write", 11},
      {"render_json", 12},
      {"ngx.say", 13},
    ])
  end

  it "skips nested local function bodies in handler callees" do
    body = <<-LUA
      local helper = function()
        Hidden.call()
      end
      return Visible.call()
      LUA

    callees = Noir::LuaCalleeExtractor.callees_for_body(body, "app.lua", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"Visible.call", 23},
    ])
  end

  it "extracts inline function bodies with nested Lua blocks" do
    source = <<-LUA
      app:get("/users", function(self)
        if self.params.id then
          return Users.find(self.params.id)
        end

        return Users.list()
      end)
      LUA

    start = source.index!("function")
    body = Noir::LuaCalleeExtractor.extract_function_after(source, start)
    body.should_not be_nil

    body.try do |body_text, start_line|
      start_line.should eq(1)
      Noir::LuaCalleeExtractor.callees_for_body(body_text, "app.lua", start_line).map { |name, _, line| {name, line} }.should eq([
        {"Users.find", 3},
        {"Users.list", 6},
      ])
    end
  end

  it "indexes named function and function-valued table bodies" do
    source = <<-LUA
      local named_profile = function(self)
        return Profiles.find(self.params.id)
      end

      function app:dashboard(self)
        return Dashboard.load()
      end
      LUA

    bodies = Noir::LuaCalleeExtractor.function_bodies(source, "app.lua")
    bodies.keys.sort!.should eq(["app:dashboard", "dashboard", "named_profile"])

    profile = bodies["named_profile"]
    Noir::LuaCalleeExtractor.callees_for_body(profile[:body], profile[:path], profile[:start_line]).map(&.[0]).should eq([
      "Profiles.find",
    ])

    dashboard = bodies["dashboard"]
    Noir::LuaCalleeExtractor.callees_for_body(dashboard[:body], dashboard[:path], dashboard[:start_line]).map(&.[0]).should eq([
      "Dashboard.load",
    ])
  end

  it "does not index fake functions from Lua comments or long strings" do
    source = <<-LUA
      --[[ dashboard = function(self)
        Ghost.call()
      end ]]

      local text = [[
        named_profile = function(self)
          Hidden.call()
        end
      ]]

      local dashboard = function(self)
        return Dashboard.load()
      end
      LUA

    bodies = Noir::LuaCalleeExtractor.function_bodies(source, "app.lua")
    bodies.keys.sort!.should eq(["dashboard"])
    dashboard = bodies["dashboard"]
    Noir::LuaCalleeExtractor.callees_for_body(dashboard[:body], dashboard[:path], dashboard[:start_line]).map(&.[0]).should eq([
      "Dashboard.load",
    ])
  end

  it "extracts MoonScript indented route bodies" do
    source = <<-MOON
      class extends lapis.Application
        "/moon": =>
          moon_service.load @params
          @render "profile"
          render_moon "home"
        "/next": =>
          next_call()
      MOON

    arrow_end = source.index!("=>") + 2
    body = Noir::LuaCalleeExtractor.extract_moonscript_block_after(source, arrow_end)
    body.should_not be_nil

    body.try do |body_text, start_line|
      start_line.should eq(3)
      Noir::LuaCalleeExtractor.callees_for_body(body_text, "app.moon", start_line).map { |name, _, line| {name, line} }.should eq([
        {"moon_service.load", 3},
        {"self.render", 4},
        {"render_moon", 5},
      ])
    end
  end

  it "treats MoonScript keywords as callees only in .moon sources" do
    body = <<-SRC
      local Animal = class("Animal")
      import("mymodule")
      return switch(Animal)
      SRC

    lua = Noir::LuaCalleeExtractor.callees_for_body(body, "app.lua", 1).map(&.[0])
    lua.should contain("class")
    lua.should contain("import")
    lua.should contain("switch")

    moon = Noir::LuaCalleeExtractor.callees_for_body(body, "app.moon", 1).map(&.[0])
    moon.should_not contain("class")
    moon.should_not contain("import")
    moon.should_not contain("switch")
  end

  it "captures a whole MoonScript respond_to action region without leaking adjacent routes" do
    source = <<-MOON
      class extends lapis.Application
        [profile: "/profile"]: respond_to {
          GET: => load_profile @params
          POST: => save_profile @params
        }
        [next: "/next"]: => other_call!
      MOON

    value_start = source.index!("respond_to") - 2 # just past the route header's ':'
    region = Noir::LuaCalleeExtractor.moonscript_value_region(source, value_start)
    region.should_not be_nil

    region.try do |text, start_line|
      start_line.should eq(2)
      text.should contain("respond_to")
      text.should contain("load_profile")
      text.should contain("save_profile")
      text.should_not contain("other_call")
    end
  end
end
