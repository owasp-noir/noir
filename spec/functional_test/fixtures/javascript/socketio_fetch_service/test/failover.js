const axios = require("axios");
const { Server } = require("socket.io");

describe("failover", () => {
  it("rejoins", async () => {
    const io = new Server(3001);

    io.on("connection", (socket) => {
      socket.on("phantom event", () => {});
    });
    await axios.get("http://localhost:3001");
  });
});
