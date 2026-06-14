const jetzig = @import("jetzig");

// A view module reached only through explicit `app.route(...)` registrations
// (it lives under `app/api/`, not `app/views/`, so resourceful routing never
// mounts it). Its action functions still supply the route callees.

pub fn index(request: *jetzig.Request) !jetzig.View {
    _ = try Product.findAll();
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request) !jetzig.View {
    _ = try Product.find(id);
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request) !jetzig.View {
    try Product.create(.{});
    return request.render(.created);
}

pub fn delete(id: []const u8, request: *jetzig.Request) !jetzig.View {
    try Product.destroy(id);
    return request.render(.ok);
}
