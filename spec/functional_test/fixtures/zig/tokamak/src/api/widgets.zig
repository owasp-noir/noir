const std = @import("std");

// Controller mounted with `.router(widgets)` under the `/api` group in
// main.zig. Each handler encodes its method + path in the function name; the
// mount composes the `/api` prefix onto them.

pub fn @"GET /widgets"(db: *Db) ![]Widget {
    return listWidgets(db);
}

pub fn @"POST /widgets"(db: *Db, data: Widget) !Widget {
    return createWidget(db, data);
}

pub fn @"GET /widgets/:id"(db: *Db, id: u32) !Widget {
    return findWidget(db, id);
}
