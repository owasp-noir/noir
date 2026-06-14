// Route module registered from main via `api.items.registerItems(router)`.
// It deliberately does NOT reference `httpz` — it only sees the re-exported
// `AppRouter` alias — so it exercises the routing-signal file gate (a file
// that bears routes but not the framework name).
const Router = @import("../api.zig").AppRouter;

pub fn registerItems(router: *Router) void {
    var items = router.group("/items", .{});
    items.get("/", listItems, .{});
    items.get("/:id", getItem, .{});
    items.post("/", createItem, .{});
}

fn listItems(_: anytype, res: anytype) !void {
    try res.write("[]");
}

fn getItem(req: anytype, _: anytype) !void {
    try lookupItem(req);
}

fn createItem(req: anytype, _: anytype) !void {
    try saveItem(req);
}
