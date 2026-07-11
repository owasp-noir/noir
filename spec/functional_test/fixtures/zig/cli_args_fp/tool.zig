const std = @import("std");
const argsParser = @import("args");
const uri = @import("uri.zig");

// Unrelated struct + unrelated `.parse` call on a DIFFERENT receiver than
// the zig-args alias. This must never be mistaken for the CLI's option
// struct: `host`/`port` must never appear as flags, and it must not steal
// the "first match" slot from the real argsParser.parseForCurrentProcess
// call below.
const NetConfig = struct {
    host: []const u8,
    port: u16,
};

const Options = struct {
    help: bool = false,
    verbose: bool = false,

    pub const shorthands = .{
        .h = "help",
        .v = "verbose",
    };
};

fn loadConfig(raw: []const u8, allocator: std.mem.Allocator) !NetConfig {
    return uri.parse(NetConfig, raw, allocator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const options = try argsParser.parseForCurrentProcess(Options, allocator, .print);
    defer options.deinit();
    _ = options;
}
