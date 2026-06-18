require "../../../spec_helper"
require "../../../../src/detector/detectors/zig/*"

describe "Detect Zig frameworks" do
  options = create_test_options

  describe Detector::Zig::Jetzig do
    instance = Detector::Zig::Jetzig.new options

    it "detects @import(\"jetzig\") in a source file" do
      instance.detect("src/app/views/root.zig", "const jetzig = @import(\"jetzig\");").should be_true
    end

    it "detects a .jetzig dependency in build.zig.zon" do
      instance.detect("build.zig.zon", ".{ .dependencies = .{ .jetzig = .{ .url = \"x\" } } }").should be_true
    end

    it "ignores an unrelated zig file" do
      instance.detect("src/main.zig", "const std = @import(\"std\");").should be_false
    end

    it "ignores a non-zig file" do
      instance.detect("main.rb", "@import(\"jetzig\")").should be_false
    end
  end

  describe Detector::Zig::Zap do
    instance = Detector::Zig::Zap.new options

    it "detects @import(\"zap\")" do
      instance.detect("src/main.zig", "const zap = @import(\"zap\");").should be_true
    end

    it "detects zigzap/zap url in build.zig.zon" do
      instance.detect("build.zig.zon", ".zap = .{ .url = \"https://github.com/zigzap/zap\" }").should be_true
    end

    it "ignores an unrelated zig file" do
      instance.detect("src/main.zig", "const httpz = @import(\"httpz\");").should be_false
    end
  end

  describe Detector::Zig::Httpz do
    instance = Detector::Zig::Httpz.new options

    it "detects @import(\"httpz\")" do
      instance.detect("src/main.zig", "const httpz = @import(\"httpz\");").should be_true
    end

    it "detects a .httpz dependency in build.zig.zon" do
      instance.detect("build.zig.zon", ".httpz = .{ .url = \"x\" }").should be_true
    end

    it "ignores an unrelated zig file" do
      instance.detect("src/main.zig", "const std = @import(\"std\");").should be_false
    end
  end

  describe Detector::Zig::Http do
    instance = Detector::Zig::Http.new options

    it "detects std.http.Server references" do
      instance.detect("src/main.zig", "const Request = std.http.Server.Request;").should be_true
    end

    it "detects receiveHead-based std server handling" do
      source = <<-ZIG
        const std = @import("std");
        fn handle(server: *std.http.Server) !void {
            var request = try server.receiveHead();
            if (std.mem.eql(u8, request.head.target, "/")) {
                try request.respond("ok", .{});
            }
        }
        ZIG

      instance.detect("src/main.zig", source).should be_true
    end

    it "ignores unrelated std imports" do
      instance.detect("src/main.zig", "const std = @import(\"std\");").should be_false
    end

    it "ignores non-zig files" do
      instance.detect("main.txt", "const Request = std.http.Server.Request;").should be_false
    end
  end

  describe Detector::Zig::Tokamak do
    instance = Detector::Zig::Tokamak.new options

    it "detects @import(\"tokamak\")" do
      instance.detect("src/main.zig", "const tk = @import(\"tokamak\");").should be_true
    end

    it "detects cztomsik/tokamak url in build.zig.zon" do
      instance.detect("build.zig.zon", ".tokamak = .{ .url = \"https://github.com/cztomsik/tokamak\" }").should be_true
    end

    it "ignores an unrelated zig file" do
      instance.detect("src/main.zig", "const zap = @import(\"zap\");").should be_false
    end
  end
end
