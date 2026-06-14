const std = @import("std");
const httpz = @import("httpz");
const api = @import("api.zig");

pub fn main() !void {
    var server = try httpz.Server().init(std.heap.page_allocator, .{ .port = 5882 }, .{});
    defer server.deinit();

    var router = try server.router(.{});

    router.get("/", index, .{});
    router.get("/users/:id", getUser, .{});
    router.post("/users", createUser, .{});
    router.delete("/users/:id", deleteUser, .{});
    router.all("/health", health, .{});
    router.method("QUERY", "/cache/:key", purgeCache, .{});

    // Prefixed route group.
    var admin = router.group("/admin", .{});
    admin.get("/stats", adminStats, .{});

    // Nested group inherits the parent prefix.
    var v1 = admin.group("/v1", .{});
    v1.get("/ping", v1Ping, .{});

    // Routes registered from a helper module that doesn't import httpz.
    api.items.registerItems(router);

    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    try res.write("home");
}

fn getUser(req: *httpz.Request, res: *httpz.Response) !void {
    const id = req.param("id").?;
    try res.json(.{ .id = id }, .{});
}

fn createUser(req: *httpz.Request, res: *httpz.Response) !void {
    try userStore.insert(req.body);
}

fn deleteUser(req: *httpz.Request, res: *httpz.Response) !void {
    try userStore.remove(req.param("id").?);
}

fn health(_: *httpz.Request, res: *httpz.Response) !void {
    try res.write("ok");
}

fn purgeCache(_: *httpz.Request, res: *httpz.Response) !void {
    try cache.purge();
}

fn adminStats(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(stats, .{});
}

fn v1Ping(_: *httpz.Request, res: *httpz.Response) !void {
    try res.write("pong");
}
