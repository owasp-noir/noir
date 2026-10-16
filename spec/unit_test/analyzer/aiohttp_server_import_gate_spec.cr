require "../../spec_helper"
# Reuses AiohttpRelevanceHarness (the `aiohttp_relevant_source?` probe).
require "./csharp_python_framework_scope_spec"

# A file that imports a competing framework is aiohttp's only when it imports
# the aiohttp SERVER half; the client (`ClientSession`) is what FastAPI and
# Sanic apps pull in for outbound requests.
describe "aiohttp server-import gate" do
  gate = AiohttpRelevanceHarness.new(create_test_options)

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

  it "keeps aiohttp off a client-only import next to Sanic, even with a parenthesised list" do
    gate.relevant?(<<-PY).should be_false
      import aiohttp
      from aiohttp import (
          ClientSession,  # (outbound only)
          TCPConnector,  # no web here
      )
      from sanic import Sanic

      app = Sanic("x")
      PY
  end

  describe "still claims an aiohttp server module that also imports a competing framework" do
    {
      "from aiohttp import web"                 => "from aiohttp import web\nroutes = web.RouteTableDef()",
      "a parenthesised multi-line from-import"  => "from aiohttp import (\n    ClientSession,\n    web,\n)\nroutes = web.RouteTableDef()",
      "a comment holding a closing parenthesis" => "from aiohttp import (\n    ClientSession,  # client (needs a timeout)\n    web,\n)\nroutes = web.RouteTableDef()",
      "a backslash-continued from-import"       => "from aiohttp import ClientSession, \\\n    web\nroutes = web.RouteTableDef()",
      "import aiohttp.web"                      => "import aiohttp.web\napp = aiohttp.web.Application()",
      "from aiohttp.web import ..."             => "from aiohttp.web import RouteTableDef\nroutes = RouteTableDef()",
      "from aiohttp import web as w"            => "from aiohttp import web as w\nroutes = w.RouteTableDef()",
      "from aiohttp import web_exceptions"      => "from aiohttp import ClientSession, web_exceptions",
      "aiohttp.web.Application()"               => "import aiohttp\napp = aiohttp.web.Application()",
      "aiohttp.web.run_app()"                   => "import aiohttp\naiohttp.web.run_app(app)",
      "aiohttp.web.RouteTableDef()"             => "import aiohttp\nroutes = aiohttp.web.RouteTableDef()",
    }.each do |spelling, server|
      it "via #{spelling}" do
        gate.relevant?("from flask import Flask\n#{server}\n").should be_true
      end
    end
  end
end
