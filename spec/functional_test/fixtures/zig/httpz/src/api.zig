const httpz = @import("httpz");

const Handler = struct {};
const Action = *const fn (*Handler, *httpz.Request, *httpz.Response) anyerror!void;

// App-local router alias re-exported to route modules. Those modules register
// routes against `AppRouter` without importing `httpz` themselves.
pub const AppRouter = httpz.Router(*Handler, Action);
pub const items = @import("api/items.zig");
