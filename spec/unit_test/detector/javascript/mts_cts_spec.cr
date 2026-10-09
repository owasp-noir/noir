require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

# `.mts` / `.cts` are TypeScript module extensions; every JS detector that
# accepts `.ts` must accept them too, or the project detects nothing.
describe "JS detectors accept .mts/.cts" do
  options = create_test_options

  samples = {
    Detector::Javascript::Express.new(options)     => "import express from 'express'",
    Detector::Javascript::Fastify.new(options)     => "import Fastify from 'fastify'",
    Detector::Javascript::Hono.new(options)        => "import { Hono } from 'hono'",
    Detector::Javascript::Koa.new(options)         => "import Koa from 'koa'",
    Detector::Javascript::Restify.new(options)     => "const restify = require(\"restify\")",
    Detector::Javascript::Apollo.new(options)      => "import { ApolloServer } from '@apollo/server'",
    Detector::Javascript::GraphqlYoga.new(options) => "import { createYoga } from 'graphql-yoga'",
    Detector::Javascript::SocketIO.new(options)    => "import { Server } from 'socket.io'",
  }

  samples.each do |detector, code|
    %w[.mts .cts].each do |ext|
      it "#{detector.class} detects #{ext}" do
        detector.detect("server#{ext}", code).should be_true
        detector.applicable?("server#{ext}").should be_true
      end
    end
  end
end
