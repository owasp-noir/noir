// A standalone Socket.IO service: no http-server import, but it calls an
// upstream API with node-fetch. That outbound client import must not make
// the file look like a test stub.
const { Server } = require("socket.io");
const fetch = require("node-fetch");

const io = new Server(3000);

io.on("connection", (socket) => {
  socket.on("lookup user", async (id) => {
    const res = await fetch("https://api.example.com/users/" + id);
    socket.emit("lookup result", await res.json());
  });
});
