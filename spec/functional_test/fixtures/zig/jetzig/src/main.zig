const std = @import("std");
const jetzig = @import("jetzig");

pub fn init(app: *jetzig.App) !void {
    // Explicit custom routes pointing at a view module outside `app/views/`.
    app.route(.GET, "/api/products", @import("app/api/products.zig"), .index);
    app.route(.GET, "/api/products/:id", @import("app/api/products.zig"), .get);
    app.route(.POST, "/api/products", @import("app/api/products.zig"), .post);
    // A commented-out registration must NOT be picked up.
    // app.route(.DELETE, "/api/products/:id", @import("app/api/products.zig"), .delete);
}
