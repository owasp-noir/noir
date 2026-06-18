const std = @import("std");

pub fn main() !void {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 8080);
    var server = try addr.listen(.{});
    defer server.deinit();

    while (true) {
        const conn = try server.accept();
        defer conn.stream.close();

        var read_buffer: [4096]u8 = undefined;
        var http_server = std.http.Server.init(conn, &read_buffer);
        var request = try http_server.receiveHead();
        try route(&request);
    }
}

fn route(request: *std.http.Server.Request) !void {
    if (request.head.method == .GET and std.mem.eql(u8, request.head.target, "/")) {
        try request.respond("ok", .{});
    } else if (std.mem.eql(u8, request.head.target, "/users") and request.head.method == .POST) {
        try createUser(request);
    } else if (request.head.method == .GET) {
        if (std.mem.eql(u8, request.head.target, "/users/:id")) {
            try getUser(request);
        }
    }

    switch (request.head.method) {
        .DELETE => {
            if (std.mem.eql(u8, request.head.target, "/users/:id")) {
                try deleteUser(request);
            }
        },
        .PATCH => {
            const target: []const u8 = request.head.target;
            if (std.mem.eql(u8, target, "/users/:id")) {
                try updateUser(request);
            }
        },
        else => {},
    }

    const path = request.head.target;
    if (std.mem.eql(u8, path, "/health")) {
        try health(request);
    }

    const method: std.http.Method = request.head.method;
    if (method == .OPTIONS and std.mem.eql(u8, request.head.target, "/options")) {
        try options(request);
    }

    switch (request.head.target) {
        "/switch-health" => {
            try switchHealth(request);
        },
        else => {},
    }
}

fn createUser(request: *std.http.Server.Request) !void {
    try request.respond("created", .{});
}

fn getUser(request: *std.http.Server.Request) !void {
    try request.respond("user", .{});
}

fn deleteUser(request: *std.http.Server.Request) !void {
    try request.respond("deleted", .{});
}

fn updateUser(request: *std.http.Server.Request) !void {
    try request.respond("updated", .{});
}

fn health(request: *std.http.Server.Request) !void {
    try request.respond("ok", .{});
}

fn options(request: *std.http.Server.Request) !void {
    try request.respond("ok", .{});
}

fn switchHealth(request: *std.http.Server.Request) !void {
    try request.respond("ok", .{});
}

test "routes in test blocks are ignored" {
    const request = fakeRequest();
    if (std.mem.eql(u8, request.head.target, "/test-only")) {
        try health(request);
    }
}
