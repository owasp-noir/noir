const std = @import("std");
const zap = @import("zap");

// Modern `zap.Endpoint` API: the whole file is the endpoint struct, but the
// supported verbs are declared as `zap.Endpoint.init(.{ .get = …, .post = … })`
// option fields rather than `pub fn get`/… methods. The path is injected at
// the `ProjectsEndpoint.init("/projects")` call site in main.zig.
pub const Self = @This();

ep: zap.Endpoint = undefined,

pub fn init(path: []const u8) Self {
    return .{
        .ep = zap.Endpoint.init(.{
            .path = path,
            .get = getProject,
            .post = postProject,
        }),
    };
}

fn getProject(_: *zap.Endpoint, r: zap.Request) !void {
    try listProjects(r);
}

fn postProject(_: *zap.Endpoint, r: zap.Request) !void {
    try saveProject(r);
}

fn listProjects(r: zap.Request) !void {
    try r.sendJson("[]");
}

fn saveProject(r: zap.Request) !void {
    try projectStore.insert(r.body);
}
