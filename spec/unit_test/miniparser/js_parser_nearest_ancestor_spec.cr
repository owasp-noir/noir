require "../../spec_helper"
require "../../../src/miniparsers/js_parser"

describe Noir::JSParser do
  describe "nearest_ancestor" do
    code = <<-JS
      const express = require('express');
      const router = express.Router();
      const comfy = express.Router();
      const deep = express.Router();
      const loner = express.Router();
      deep.get('/leaf', (req, res) => {});
      comfy.use('/deep', deep);
      router.use('/comfy', comfy);
      loner.get('/x', (req, res) => {});
      JS

    parser = Noir::JSParser.new(code)
    parser.parse_routes

    it "starts at the router itself" do
      parser.nearest_ancestor("comfy") { |name| name == "comfy" }.should eq("comfy")
    end

    it "walks the in-file mount chain up to the first match" do
      parser.nearest_ancestor("deep") { |name| name == "router" }.should eq("router")
      parser.nearest_ancestor("deep") { |name| name == "comfy" }.should eq("comfy")
    end

    it "returns nil when no router on the chain matches" do
      parser.nearest_ancestor("loner") { |name| name == "router" }.should be_nil
      parser.nearest_ancestor("unknown") { |_| false }.should be_nil
    end

    it "terminates on a mount cycle" do
      cyclic = Noir::JSParser.new(<<-JS)
        const a = express.Router();
        const b = express.Router();
        a.use('/b', b);
        b.use('/a', a);
        a.get('/x', (req, res) => {});
        JS
      cyclic.parse_routes
      cyclic.nearest_ancestor("a") { |name| name == "nope" }.should be_nil
    end
  end
end
