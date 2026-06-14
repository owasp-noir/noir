const std = @import("std");
const zap = @import("zap");
const UsersEndpoint = @import("users.zig");
const HealthEndpoint = @import("health.zig");
const Endpoints = @import("endpoints.zig");

const Handlers = struct {
    pub fn stats(_: *Handlers, r: zap.Request) !void {
        try r.sendJson("{}");
    }
};

fn ping(r: zap.Request) !void {
    try r.sendBody("pong");
}

pub fn main() !void {
    var users = UsersEndpoint.init("/users");
    _ = &users;

    var health: HealthEndpoint = .{};
    _ = &health;

    // Namespaced struct literal — the `Comments` type is reached via the
    // `Endpoints` re-export and bound to `/comments` here.
    var comments = Endpoints.Comments{ .path = "/comments" };
    _ = &comments;

    var router = zap.Router.init(std.heap.page_allocator, .{});
    defer router.deinit();

    var handlers = Handlers{};
    try router.handle_func("/stats", &handlers, &Handlers.stats);
    try router.handle_func_unbound("/ping", ping);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = router.on_request_handler(),
    });
    try listener.listen();
}
