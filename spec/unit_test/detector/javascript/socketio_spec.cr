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
end
