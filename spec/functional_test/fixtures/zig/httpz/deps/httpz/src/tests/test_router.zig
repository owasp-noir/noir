const httpz = @import("../httpz.zig");

// This file belongs to a *vendored copy of the httpz framework* checked into
// the source tree (`deps/httpz/…`), not to the application. Its route literal
// must NOT surface as an app endpoint — the analyzer skips vendored framework
// trees. If the skip regresses, `/vendored-phantom` would push the endpoint
// count over the expected total and fail the functional test.
test "router registers a route" {
    var router = testRouter();
    router.get("/vendored-phantom", phantomHandler, .{});
}

fn phantomHandler(_: *httpz.Request, res: *httpz.Response) !void {
    try res.write("phantom");
}
