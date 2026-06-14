require "spec"
require "../../../src/miniparsers/zig_callee_extractor"

describe Noir::ZigCalleeExtractor do
  it "extracts receiver-chain and bare callees, skipping keywords and builtins" do
    body = <<-ZIG
        const user = try userStore.find(id);
        if (user == null) return error.NotFound;
        try res.json(user, .{});
        log("done");
        const t = @import("std");
      ZIG

    callees = Noir::ZigCalleeExtractor.callees_for_body(body, "main.zig", 10)
    names = callees.map { |name, _, _| name }
    names.should contain("userStore.find")
    names.should contain("res.json")
    names.should contain("log")
    # `if`, `return`, `try`, the `@import` builtin and `error.NotFound` (no call
    # paren) must not surface as callees.
    names.should_not contain("if")
    names.should_not contain("return")
    names.should_not contain("@import")
  end

  it "drops calls inside comments and string literals" do
    body = <<-ZIG
        realCall();
        // commentedCall();
        const s = "stringCall()";
        const doc =
            \\\\ multilineCall()
        ;
      ZIG

    names = Noir::ZigCalleeExtractor.callees_for_body(body, "main.zig", 1).map { |n, _, _| n }
    names.should contain("realCall")
    names.should_not contain("commentedCall")
    names.should_not contain("stringCall")
    names.should_not contain("multilineCall")
  end

  it "filters std.* noise roots" do
    body = <<-ZIG
        std.debug.print("x", .{});
        businessLogic();
      ZIG

    names = Noir::ZigCalleeExtractor.callees_for_body(body, "main.zig", 1).map { |n, _, _| n }
    names.should contain("businessLogic")
    names.should_not contain("std.debug.print")
  end

  it "indexes function bodies by name with correct start lines" do
    source = <<-ZIG
      const std = @import("std");

      pub fn handler(req: *Request) !void {
          try doWork();
      }

      fn helper() void {}
      ZIG

    bodies = Noir::ZigCalleeExtractor.function_bodies(source, "main.zig")
    bodies.has_key?("handler").should be_true
    bodies.has_key?("helper").should be_true
    bodies["handler"][:body].should contain("doWork")
    bodies["handler"][:start_line].should eq(3)
  end

  it "preserves string contents in strip_comments but blanks comments" do
    source = "const p = \"/api/users\"; // route\n"
    stripped = Noir::ZigCalleeExtractor.strip_comments(source)
    stripped.should contain("/api/users")
    stripped.should_not contain("route")
  end

  it "skips anonymous struct return types when locating the body brace" do
    source = <<-ZIG
      fn make() struct { x: u32 } {
          return build();
      }
      ZIG

    bodies = Noir::ZigCalleeExtractor.function_bodies(source, "main.zig")
    bodies.has_key?("make").should be_true
    bodies["make"][:body].should contain("build")
    bodies["make"][:body].should_not contain("x: u32")
  end
end
