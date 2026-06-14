const jetzig = @import("jetzig");
const Post = @import("../models/Post.zig");

pub fn index(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    const posts = try Post.findAll(request.allocator);
    try data.put("posts", posts);
    return request.render(.ok);
}

pub fn get(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    const post = try Post.find(id);
    _ = post;
    return request.render(.ok);
}

pub fn new(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    return request.render(.ok);
}

pub fn edit(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = id;
    return request.render(.ok);
}

pub fn post(request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    const params = try request.params();
    const title = params.get("title");
    _ = title;
    try Post.create(params);
    return request.render(.created);
}

pub fn put(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = id;
    return request.render(.ok);
}

pub fn patch(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    _ = id;
    return request.render(.ok);
}

pub fn delete(id: []const u8, request: *jetzig.Request, data: *jetzig.Data) !jetzig.View {
    try Post.destroy(id);
    return request.render(.ok);
}
