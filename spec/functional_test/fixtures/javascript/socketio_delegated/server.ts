import { io } from "./app";
import { chatHandler } from "./handlers/chat";
import registerAdmin from "./handlers/admin";

// This module builds no server of its own: `io` comes from ./app.
io.on("connection", async (socket) => {
    socket.emit("hello");

    socket.on("ping me", (callback) => {
        callback("pong");
    });

    chatHandler(socket);
    registerAdmin(socket, io);
});
