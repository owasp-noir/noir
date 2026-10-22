const http = require("http");
const { Server } = require("socket.io");

const httpServer = http.createServer();
const io = new Server(httpServer);

io.on("connection", (socket) => {
  socket.on("real event", (msg) => {
    io.emit("real event", msg);
  });
});
