const std = @import("std");

// Controllers declared as `pub const @"METHOD /path" = handler;` bindings
// rather than functions. The handler is defined elsewhere, so these routes
// carry no inline callees. Each struct is mounted by qualified name
// (`.router(resources.Public)`); its routes inherit only the prefix of the
// mount that selects that struct.

pub const Public = struct {
    pub const @"GET /ping" = ping;
    pub const @"POST /login" = login;
};

pub const Private = struct {
    pub const @"DELETE /sessions/:id" = dropSession;
};

fn ping() ![]const u8 {
    return "pong";
}

fn login() !void {}

fn dropSession() !void {}
