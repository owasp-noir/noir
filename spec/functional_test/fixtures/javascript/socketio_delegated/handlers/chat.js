const { checkLogin, requireLogin } = require("../auth");

const prefix = "chat_";

/**
 * @param {Socket} socket
 */
module.exports.chatHandler = (socket) => {
    socket.on("send", async (msg, callback) => {
        try {
            checkLogin(socket);
            callback({ ok: true, msg });
        } catch (e) {
            callback({ ok: false });
        }
    });

    socket.on(prefix + "join", async (room) => {
        requireLogin(socket);
        socket.join(room);
    });

    // A prefix that is not a string constant of this file is not guessed.
    socket.on(otherPrefix + "leave", () => {});

    socket.on("history", async (callback) => {
        try {
            callback([]);
        } catch (e) {
            checkLogin(socket);
        }
    });
};
