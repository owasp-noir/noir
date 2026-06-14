const std = @import("std");
const zap = @import("zap");

pub const UsersEndpoint = @This();

// Path injected at construction time (see main.zig's `init("/users")`).
path: []const u8,

pub fn init(p: []const u8) UsersEndpoint {
    return .{ .path = p };
}

pub fn get(_: *UsersEndpoint, r: zap.Request) !void {
    try listUsers(r);
}

pub fn post(_: *UsersEndpoint, r: zap.Request) !void {
    try createUser(r);
}

fn listUsers(r: zap.Request) !void {
    try r.sendJson("[]");
}

fn createUser(r: zap.Request) !void {
    try userStore.insert(r.body);
}
