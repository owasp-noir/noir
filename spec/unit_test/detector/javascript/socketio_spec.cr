require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JavaScript Socket.IO" do
  options = create_test_options
  instance = Detector::Javascript::SocketIO.new options

  it "detects a require('socket.io') server" do
    src = <<-JS
      const { Server } = require("socket.io");
      const io = new Server(3000);
      io.on("connection", (s) => s.on("msg", () => {}));
      JS
    instance.detect("server.js", src).should be_true
  end

  it "detects an ESM import from 'socket.io'" do
    instance.detect("server.ts", "import { Server } from 'socket.io';").should be_true
  end

  it "detects a socket.io dependency in package.json" do
    pkg = %({"dependencies": {"socket.io": "^4.7.0"}})
    instance.detect("package.json", pkg).should be_true
  end

  it "ignores the browser client (socket.io-client)" do
    instance.detect("client.js", "import { io } from 'socket.io-client';").should be_false
  end

  it "ignores a plain express file" do
    instance.detect("app.js", "const express = require('express'); const app = express();").should be_false
  end

  it "ignores a plain `ws` server that also builds a `new Server(`" do
    src = <<-JS
      const { Server } = require('ws');

      const wss = new Server({ port: 8080 });
      wss.on('connection', (socket) => {
        socket.on('message', (data) => socket.send(data));
      });
      JS
    instance.detect("server.js", src).should be_false
  end

  it "ignores a gRPC server built from a `Server` import" do
    src = <<-JS
      import { Server, ServerCredentials } from '@grpc/grpc-js';

      const server = new Server();
      process.on('SIGTERM', () => server.tryShutdown(() => {}));
      JS
    instance.detect("server.ts", src).should be_false
  end

  it "detects a minimal `new Server(` server through its emitter" do
    src = <<-JS
      const io = new Server(httpServer);
      io.on("connection", (socket) => {
        socket.on("msg", (m) => io.emit("msg", m));
      });
      JS
    instance.detect("server.js", src).should be_true
  end

  it "detects a `new Server(` paired with a nested room emit" do
    src = <<-JS
      const io = new Server(httpServer);
      io.to(roomFor(id)).emit("update", payload);
      JS
    instance.detect("server.js", src).should be_true
  end

  it "detects a `new Server(` paired with a Socket.IO namespace" do
    src = <<-JS
      const io = new Server(httpServer);
      const admin = io.of("/admin");
      admin.on("connection", (socket) => socket.on("ban", () => {}));
      JS
    instance.detect("server.js", src).should be_true
  end
end
