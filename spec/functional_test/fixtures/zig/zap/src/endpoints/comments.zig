const std = @import("std");
const zap = @import("zap");

// Idiomatic `const Self = @This();` endpoint struct. The path is bound at the
// namespaced instantiation site in main.zig (`Endpoints.Comments{ .path =
// "/comments" }`), NOT here, so the `path` field default is a dead value that
// the binding must override.
const Self = @This();

path: []const u8 = "/unused",

pub fn get(_: *Self, r: zap.Request) !void {
    try listComments(r);
}

pub fn post(_: *Self, r: zap.Request) !void {
    try createComment(r);
}

fn listComments(r: zap.Request) !void {
    try r.sendJson("[]");
}

fn createComment(r: zap.Request) !void {
    try commentStore.insert(r.body);
}
