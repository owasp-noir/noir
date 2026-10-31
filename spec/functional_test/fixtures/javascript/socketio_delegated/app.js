const http = require("http");
const { Server } = require("socket.io");

const httpServer = http.createServer();
module.exports.io = new Server(httpServer);
