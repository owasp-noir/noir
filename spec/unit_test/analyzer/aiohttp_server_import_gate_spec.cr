require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/analyzer/analyzers/python/aiohttp"

class AiohttpServerGateHarness < Analyzer::Python::Aiohttp
  def relevant?(source : String) : Bool
    aiohttp_relevant_source?(source)
  end
end

describe "aiohttp server-import gate" do
  gate = AiohttpServerGateHarness.new(create_test_options)

  it "keeps aiohttp off a FastAPI router that only imports the client" do
    gate.relevant?(<<-PY).should be_false
      from aiohttp import BasicAuth, ClientSession
      from fastapi import APIRouter

      router = APIRouter()

      @router.post("/signin")
      async def signin():
          return {}
      PY
  end

  it "still claims an aiohttp server module that also imports a competing framework" do
    gate.relevant?(<<-PY).should be_true
      from aiohttp import web
      from flask import Flask

      routes = web.RouteTableDef()
      PY

    gate.relevant?(<<-PY).should be_true
      from aiohttp import (
          ClientSession,
          web,
      )
      from fastapi import FastAPI

      routes = web.RouteTableDef()
      PY

    gate.relevant?(<<-PY).should be_true
      import aiohttp.web
      from sanic import Sanic

      app = aiohttp.web.Application()
      PY
  end
end
