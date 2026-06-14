const std = @import("std");
const tk = @import("tokamak");

const routes: []const tk.Route = &.{
    .get("/", hello),
    .post("/users", createUser),
    .group("/api", &.{
        .get("/health", health),
        .group("/v1", &.{
            .get("/items/:id", getItem),
            .delete("/items/:id", deleteItem),
        }),
    }),
};

fn hello() ![]const u8 {
    return greet("world");
}

fn createUser(req: *tk.Request) !void {
    try db.insert(req.body);
    audit.log("create");
}

fn health() ![]const u8 {
    return "ok";
}

fn getItem() !void {
    try store.fetch();
}

fn deleteItem() !void {
    try store.remove();
}

pub fn main() !void {
    var server = try tk.Server.init(std.heap.page_allocator, routes, .{ .listen = .{ .port = 8080 } });
    defer server.deinit();
    try server.start();
}
