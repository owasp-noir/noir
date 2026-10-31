// Uses `net` to probe a port, but its sockets are Socket.IO's: the
// exclusion is for a raw server's own connections only.
const net = require("net");
const { Server } = require("socket.io");
const io = new Server(5000);

function checkLog(socket) {
    log.debug("auth", "checking " + socket.id);
    if (!socket.userID) {
        throw new Error("not logged in");
    }
}

function checkRethrow(socket) {
    try {
        if (!socket.userID) {
            throw new Error("not logged in");
        }
    } catch (e) {
        throw e;
    }
}

function checkLogged(socket) {
    if (!socket.logged) throw new Error("no");
}

io.on("connection", (socket) => {
    socket.on("log_first", async (d, cb) => {
        log.info("socket", "event " + d);
        checkLogin(socket);
        await db.remove(d);
    });
    socket.on("awaited_read_first", async (slug, cb) => {
        const id = await StatusPage.slugToID(slug);
        checkLogin(socket);
        await db.remove(id);
    });
    socket.on("awaited_write_first", async (d, cb) => {
        const row = await db.insertRow(d);
        checkLogin(socket);
        cb(row);
    });
    socket.on("chained_declaration", async (d, cb) => {
        const ids = d.items
            .map((x) => x.id)
            .filter(Boolean);
        checkLogin(socket);
        await db.remove(ids);
    });
    socket.on("call_in_shuffle", async (d, cb) => {
        if (db.removeAllSync(d)) {
            cb = noop;
        }
        checkLogin(socket);
    });
    socket.on("helper_logs", async (d, cb) => {
        checkLog(socket);
        await db.remove(d);
    });
    socket.on("helper_rethrows", async (d, cb) => {
        checkRethrow(socket);
        await db.remove(d);
    });
    socket.on("helper_logged", async (d, cb) => {
        checkLogged(socket);
        await db.remove(d);
    });
    socket.on("probe_port", async (port, cb) => {
        checkLogin(socket);
        net.connect(port);
    });
    // Writes dressed as declarations or log lines: none is a read.
    socket.on("fetch_post", async (d, cb) => {
        const r = await fetch(d.url, { method: "POST" });
        checkLogin(socket);
    });
    socket.on("raw_query", async (d, cb) => {
        const rows = await db.query("DELETE FROM t WHERE id = ?", [d.id]);
        checkLogin(socket);
    });
    socket.on("builder_delete", async (d, cb) => {
        const n = await knex("t").where({ id: d.id }).del();
        checkLogin(socket);
    });
    socket.on("sync_write", async (d, cb) => {
        const info = db.prepare("DELETE FROM t WHERE id = ?").run(d.id);
        checkLogin(socket);
    });
    socket.on("log_with_write", async (d, cb) => {
        log.info("x", await db.remove(d.id));
        checkLogin(socket);
    });
    socket.on("decrement", async (d, cb) => {
        const a = d.id
        --quota[a]
        checkLogin(socket);
    });
});

function checkLogin(socket) {
    if (!socket.userID) throw new Error("not logged in");
}
