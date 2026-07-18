const http = require("http");
const { Server } = require("socket.io");

const httpServer = http.createServer();
const io = new Server(httpServer);

// Non-socket emitters that co-locate with the server must NOT surface as
// realtime events — their receivers are never bound as a connection socket.
httpServer.on("error", (err) => console.error(err));
process.on("SIGTERM", () => io.close());

// Default namespace connection handler.
io.on("connection", (socket) => {
  socket.on("chat message", (msg) => {
    io.emit("chat message", msg); // outbound: server -> client, ignored
  });

  socket.on("join room", (room) => {
    socket.join(room);
  });

  socket.on("disconnect", () => {
    // reserved lifecycle event, ignored
  });
});

// A named namespace with its own connection handler.
const admin = io.of("/admin");
admin.on("connection", (socket) => {
  socket.on("ban user", (id) => {
    io.emit("banned", id);
  });
});
