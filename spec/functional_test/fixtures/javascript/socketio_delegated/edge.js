const { Server } = require("socket.io");
const io = new Server(4000);
const { checkLogin } = require("./auth");

function checkNested(socket) {
    if (socket.handshake.query.debug) {
        if (!socket.userID) throw new Error("x");
    }
}

function checkSetting(socket) {
    if (process.env.DISABLE_AUTH) return;
    if (!socket.userID) throw new Error("x");
}

function checkConnected(socket) {
    if (!socket.connected) throw new Error("socket closed");
}

io.on("connection", (socket) => {
    socket.on("after_write", async (d, cb) => {
        await db.remove(d.id);
        checkLogin(socket);
        cb();
    });
    socket.on("public_branch", async (id, cb) => {
        if (isPublic(id)) {
            return cb(await db.secret(id));
        }
        checkLogin(socket);
        cb();
    });
    socket.on("unbraced_if", async (d, cb) => {
        if (d.x)
            checkLogin(socket);
        await db.remove(d);
    });
    socket.on("nested_check", async (d, cb) => {
        checkNested(socket);
        await db.remove(d);
    });
    socket.on("setting_check", async (d, cb) => {
        checkSetting(socket);
        await db.remove(d);
    });
    socket.on("not_a_session", async (d, cb) => {
        checkConnected(socket);
        await db.remove(d);
    });
    socket.on("function_style", function (d, cb) {
        checkLogin(socket);
        db.remove(d);
    });
    socket.on("one_line_try", async (d, cb) => {
        try { checkLogin(socket); await db.remove(d); } catch (e) {}
    });
    socket.on("write_in_try", async (d, cb) => {
        try { await db.remove(d); checkLogin(socket); } catch (e) {}
    });
    socket.on("shuffled_args", async (id, all, cb) => {
        if (typeof all === "function") {
            cb = all;
            all = false;
        }
        checkLogin(socket);
        cb();
    });
});
