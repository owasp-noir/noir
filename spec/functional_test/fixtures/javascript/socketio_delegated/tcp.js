// A node:net server: its sockets emit `data`, not Socket.IO events.
const net = require("net");
const server = net.createServer();
server.on("connection", (socket) => {
    socket.on("data", (chunk) => {
        socket.emit("handled", chunk);
    });
});
server.listen(9000);
