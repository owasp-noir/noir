const std = @import("std");
const argsParser = @import("args");

const Options = struct {
    help: bool = false,
    verbose: bool = false,
    output: ?[]const u8 = null,

    pub const shorthands = .{
        .h = "help",
        .v = "verbose",
        .o = "output",
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const options = try argsParser.parseForCurrentProcess(Options, allocator, .print);
    defer options.deinit();

    const token = std.process.getEnvVarOwned(allocator, "API_TOKEN");
    _ = token;
    _ = options;
}
