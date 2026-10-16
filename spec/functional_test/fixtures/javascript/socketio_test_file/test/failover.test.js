const http = require("http");
const { Server } = require("socket.io");

describe("failover", () => {
  it("rejoins", () => {
    const httpServer = http.createServer();
    const io = new Server(httpServer);

    io.on("connection", (socket) => {
      socket.on("phantom event", () => {});
    });
  });
});
