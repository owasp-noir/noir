// A plain `ws` server: its connection callback is not Socket.IO.
const { WebSocketServer } = require("ws");
const { chatHandler } = require("./handlers/chat");

const wss = new WebSocketServer({ port: 8080 });
wss.on("connection", (ws) => {
    ws.on("raw message", (data) => ws.send(data));
    chatHandler(ws);
});
