const std = @import("std");
const zap = @import("zap");

pub const HealthEndpoint = @This();

// Path declared as a struct field default.
path: []const u8 = "/health",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

pub fn get(_: *HealthEndpoint, _: std.mem.Allocator, r: zap.Request) !void {
    try r.sendBody("ok");
}
