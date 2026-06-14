const std = @import("std");
const tk = @import("tokamak");
const widgets = @import("api/widgets.zig");
const resources = @import("api/resources.zig");

const routes: []const tk.Route = &.{
    .get("/", hello),
    .post("/users", createUser),
    .group("/api", &.{
        .get("/health", health),
        // Controller mount — widgets routes compose the `/api` prefix.
        .router(widgets),
        .group("/v1", &.{
            .get("/items/:id", getItem),
            .delete("/items/:id", deleteItem),
        }),
    }),
    // Qualified struct mounts — each struct's `pub const @"…"` routes compose
    // the `/admin` prefix, partitioned by struct.
    .group("/admin", &.{
        .router(resources.Public),
        .router(resources.Private),
    }),
    // Value-form group: the body is a single route value (`.router(local)`),
    // not a `&.{ … }` array, so the `/svc` prefix is scoped to the group call's
    // own parentheses. `local` is a struct declared in this file.
    .group("/svc", .router(local)),
};

// Local controller struct mounted by the value-form group above. Its root
// handler (`@"GET /"`) collapses to `/svc` without a trailing slash.
const local = struct {
    pub fn @"GET /"() ![]const u8 {
        return ping();
    }

    pub fn @"POST /sync"() !void {
        try worker.run();
    }
};

fn hello() ![]const u8 {
    return greet("world");
}

fn createUser(req: *tk.Request) !void {
    try db.insert(req.body);
    audit.log("create");
    // Data-object `.put` with a non-rooted key — must NOT become a `PUT /name`
    // route (the leading-slash guard rejects it).
    try root.put("name", req.body);
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

test "routes" {
    // Inline routes and a controller handler declared inside a `test { … }`
    // block are unit-test fixtures — neither may be emitted as an endpoint.
    const test_routes: []const tk.Route = &.{
        .get("/test-only", hello),
    };
    _ = test_routes;
}

test "controller route fixture" {
    const Fixture = struct {
        pub fn @"GET /test-only/fn"() !void {}
    };
    _ = Fixture;
}
