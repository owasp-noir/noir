const std = @import("std");
// A local module happens to be named "args" but has nothing to do with
// process argv parsing (e.g. template/macro argument expansion). It must
// never be treated as zig-args evidence: no `parseForCurrentProcess`/`parse`
// call bound to this alias exists anywhere in the file, so no `cli://`
// endpoint should be emitted for it.
const args = @import("args");

pub fn expandTemplateArgs(raw: []const u8) []const u8 {
    return args.expand(raw);
}

pub fn main() !void {
    std.debug.print("hi\n", .{});
}
