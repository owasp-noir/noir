const jetzig = @import("jetzig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = id;
    return request.render(.ok);
}

pub fn edit(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = id;
    return request.render(.ok);
}
