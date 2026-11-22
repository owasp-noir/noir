require "../../../spec_helper"
require "../../../../src/detector/detector"

# `.mts` / `.cts` are TypeScript module extensions; every JS detector that
# accepts `.ts` must accept them too, or the project detects nothing.
describe "JS detectors accept .mts/.cts" do
  registry = build_detector_list(create_test_options).index_by(&.name)

  samples = {
    registry["js_express"]      => "import express from 'express'",
    registry["js_fastify"]      => "import Fastify from 'fastify'",
    registry["js_hono"]         => "import { Hono } from 'hono'",
    registry["js_koa"]          => "import Koa from 'koa'",
    registry["js_restify"]      => "const restify = require(\"restify\")",
    registry["js_apollo"]       => "import { ApolloServer } from '@apollo/server'",
    registry["js_graphql_yoga"] => "import { createYoga } from 'graphql-yoga'",
    registry["js_socketio"]     => "import { Server } from 'socket.io'",
  }

  samples.each do |detector, code|
    %w[.mts .cts].each do |ext|
      it "#{detector.name} detects #{ext}" do
        detector.detect("server#{ext}", code).should be_true
        detector.applicable?("server#{ext}").should be_true
      end
    end
  end
end
