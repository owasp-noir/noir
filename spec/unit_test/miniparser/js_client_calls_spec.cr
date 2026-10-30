require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_parser"
require "../../../src/miniparsers/js_route_extractor"

private def parsed(code : String, this_receiver_ok : Bool = true) : Array(String)
  Noir::JSParser.new(code, this_receiver_ok: this_receiver_ok).parse_routes.map { |r| "#{r.method} #{r.path}" }
end

describe "outbound client calls read as routes" do
  describe "JSParser client receivers" do
    it "drops browser and injected-client receivers" do
      {
        "$.get('/x', function (d) {});",
        "$.post('/x', { a: 1 }, fn);",
        "jQuery.post('/x', data, fn);",
        "this.$http.get('/x', fn);",
        "AJAX.post('/apps/x/upload', data);",
        "ajax.put('/x', data);",
        "http.get('http://localhost/x', fn);",
        "https.get('https://example.com/x', (res) => { res.resume(); });",
        "http.get('/x', (res) => { res.resume(); });",
        "io.socket.get('/x', fn);",
        "socket.post('/x', data, function (res) {});",
        "const r = await http.post('/x', data);",
        "this.http.post('/api/users', user);",
        "this.httpClient.post('/pet', body, headers);",
        "this.axiosInstance.post('/hook', payload);",
        "axiosClient.patch('/x', payload);",
      }.each do |code|
        parsed(code).should be_empty
      end
    end

    it "keeps a receiver the file builds from a server factory" do
      parsed("const express = require('express');\nconst http = express();\nhttp.get('/x', (req, res) => {});").should eq(["GET /x"])
      parsed("const express = require('express');\nconst client = express();\nclient.get('/x', (req, res) => {});").should eq(["GET /x"])
    end

    it "keeps an api receiver, which may name a real router" do
      parsed("const express = require('express');\nconst api = express.Router();\napi.get('/x', (req, res) => {});").should eq(["GET /x"])
    end
  end

  describe "JSParser this receiver" do
    it "reads a bare this.<verb>(...) when the file has server evidence" do
      parsed("class Api { constructor() { this.get('/x', (c) => c.text('ok')); } }").should eq(["GET /x"])
    end

    it "drops it when told the file imports no server framework" do
      parsed("class ProjectService { create(data) { return this.post('/api/projects/', data); } }", this_receiver_ok: false).should be_empty
      parsed("class ProjectService { list(q) { return this.get('/api/projects/', q); } }", this_receiver_ok: false).should be_empty
      parsed("class ProjectService { create() { return this.post('/api/projects/', this.payload); } }", this_receiver_ok: false).should be_empty
      parsed("class ProjectService { create() { return this.post('/api/projects/', { a: 1 }, headers); } }", this_receiver_ok: false).should be_empty
      parsed("class ProjectService { create() { return this.post('/api/projects/', buildBody(), headers); } }", this_receiver_ok: false).should be_empty
    end

    it "keeps an inline function handler even without server evidence" do
      # Unleash's controllers extend a local `Controller` and import no server.
      {
        "class B extends Controller { constructor() { super(); this.get('/prometheus', async (_req, res) => { res.end(); }); } }",
        "class B extends Controller { constructor() { super(); this.get('/prometheus', (req, res) => { res.end(); }); } }",
        "class B extends Controller { constructor() { super(); this.get('/prometheus', function (req, res) { res.end(); }); } }",
        "class B extends Controller { constructor() { super(); this.get('/prometheus', auth, async (req, res) => { res.end(); }); } }",
      }.each do |code|
        parsed(code, this_receiver_ok: false).uniq!.should eq(["GET /prometheus"])
      end
    end

    it "does not touch an explicit this.<router>.<verb>(...) receiver" do
      parsed("class Routes { init() { this.router.get('/x', (req, res) => {}); } }", this_receiver_ok: false).uniq!.should eq(["GET /x"])
    end
  end

  describe "JSRouteExtractor.extract_routes" do
    it "drops this.<verb>(...) calls of an API client class with no server import" do
      content = <<-TS
        import { APIService } from "@/services/api.service";
        export class ProjectService extends APIService {
          async createProject(slug: string, data: object) {
            return this.post(`/api/workspaces/${slug}/projects/`, data);
          }
        }
        TS
      file = File.tempfile("project.service", ".ts", &.print(content))
      begin
        Noir::JSRouteExtractor.extract_routes(file.path, content).should be_empty
      ensure
        file.delete
      end
    end

    it "keeps a controller's this.<verb>(path, inline handler) with no server import" do
      content = <<-TS
        import Controller from './controller.js';

        class BackstageController extends Controller {
          constructor(config) {
            super(config);
            this.get('/prometheus', async (_req, res) => {
              res.end('metrics');
            });
          }
        }
        TS
      file = File.tempfile("backstage", ".ts", &.print(content))
      begin
        Noir::JSRouteExtractor.extract_routes(file.path, content).map(&.url).uniq!.should eq(["/prometheus"])
      ensure
        file.delete
      end
    end

    it "keeps this.<verb>(...) in a Hono subclass" do
      content = <<-TS
        import { Hono } from "hono";
        export class Api extends Hono {
          constructor() {
            super();
            this.get("/ping", (c) => c.text("ok"));
          }
        }
        TS
      file = File.tempfile("api", ".ts", &.print(content))
      begin
        Noir::JSRouteExtractor.extract_routes(file.path, content).map(&.url).should eq(["/ping"])
      ensure
        file.delete
      end
    end

    it "keeps this.<verb>(...) in a koa-router subclass" do
      content = <<-JS
        const Router = require('koa-router');
        class Api extends Router {
          constructor() {
            super();
            this.get('/ping', async (ctx) => { ctx.body = 'ok'; });
          }
        }
        JS
      file = File.tempfile("api", ".js", &.print(content))
      begin
        Noir::JSRouteExtractor.extract_routes(file.path, content).map(&.url).should eq(["/ping"])
      ensure
        file.delete
      end
    end

    it "drops a returned this.<verb> call in a file that imports a server framework" do
      {
        "import { Context } from 'koa'; class ItemClient extends RestClient { async find(ctx: Context, id) { return await this.get(`/internal/api/items/${id}`, {}, headers(ctx)); } }",
        "import { Context } from 'koa'; class ItemClient extends RestClient { find(ctx: Context, id) { return this.get(`/internal/api/items/${id}`, {}, headers(ctx)); } }",
      }.each do |code|
        parsed(code, this_receiver_ok: true).should be_empty
      end
      parsed("class Api extends Router { constructor() { super(); this.get('/x', auth, ctrl.list); } }", this_receiver_ok: true).uniq!.should eq(["GET /x"])
    end

    it "drops a call on a member of a client module and any awaited call" do
      {
        "import * as request from './request'; async function up(id, payload) { await request.formData.post(`/form-data/items/${id}/icon`, payload); }",
        "import * as request from './request'; function up(id, payload) { request.formData.post(`/form-data/items/${id}/icon`, payload); }",
        "async function up(payload) { await api.post('/upload', payload); }",
      }.each do |code|
        parsed(code).should be_empty
      end
    end

    it "keeps router objects and route values that are not client calls" do
      {
        "const client = express.Router(); client.get('/x', ctrl.list);",
        "const api = express.Router(); api.post('/x', auth, ctrl.create);",
        "const route = app.get('/x', (c) => c.json({}));",
        "export default app.post('/x', (c) => c.text('ok'));",
        "class R { init() { this.router.get('/x', (req, res) => {}); } }",
      }.each do |code|
        parsed(code).uniq!.size.should eq(1)
      end
    end
  end

  describe "JSRouteExtractor.test_stub_only? client-side stores" do
    it "skips a MobX store that imports no UI framework" do
      content = <<-TS
        import { action } from "mobx";
        import * as Sentry from "@sentry/react";
        import { client } from "~/utils/ApiClient";
        await client.post(`/users.delete`, data);
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/app/stores/AuthStore.ts", content).should be_true
    end

    it "skips redux, zustand, swr, react-query, vuex, jquery and k6 clients" do
      {
        "import { createStore } from 'redux';",
        "import { connect } from \"react-redux\";",
        "import { configureStore } from '@reduxjs/toolkit';",
        "import create from 'zustand';",
        "import useSWR from 'swr';",
        "import { useQuery } from '@tanstack/react-query';",
        "import { createStore } from 'vuex';",
        "import $ from 'jquery';",
        "import http from 'k6/http';",
      }.each do |import_line|
        Noir::JSRouteExtractor.test_stub_only?("/app/src/client.js", "#{import_line}\nclient.post('/x', data);").should be_true
      end
    end

    it "keeps a server file that also imports mobx or redux" do
      content = <<-JS
        import express from "express";
        import { observable } from "mobx";
        const app = express();
        app.get("/state", (req, res) => res.json({}));
        JS
      Noir::JSRouteExtractor.test_stub_only?("/app/src/server.js", content).should be_false
    end

    it "does not take a swr-prefixed or redux-prefixed module for the client libraries" do
      Noir::JSRouteExtractor.test_stub_only?("/app/src/server.js", "import x from 'swr-cache-server';\napp.get('/x', h);").should be_false
      Noir::JSRouteExtractor.test_stub_only?("/app/src/server.js", "import x from 'redux-saga-server';\napp.get('/x', h);").should be_false
    end

    it "skips browser-side specs under tests/frontend/" do
      content = "api.get('/export/html', function (data) {});"
      Noir::JSRouteExtractor.test_stub_only?("/app/src/tests/frontend/specs/export.js", content).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/test/frontend/export.js", content).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/src/frontend/export.js", content).should be_false
    end
  end
end
