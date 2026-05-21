require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS GraphQL Yoga" do
  options = create_test_options
  instance = Detector::Javascript::GraphqlYoga.new options

  it "esm import from graphql-yoga" do
    instance.detect("server.ts",
      "import { createYoga, createSchema } from 'graphql-yoga';").should be_true
  end

  it "scoped @graphql-yoga subpath import" do
    instance.detect("server.ts",
      "import { useDeferStream } from '@graphql-yoga/plugin-defer-stream';").should be_true
  end

  it "require('graphql-yoga')" do
    instance.detect("server.js",
      "const { createYoga } = require('graphql-yoga')").should be_true
  end

  it "bare createYoga call (re-exported wrappers)" do
    instance.detect("server.ts", "export const yoga = createYoga({ schema });").should be_true
  end

  it "ts/tsx/jsx/mjs/cjs are applicable" do
    code = "import { createYoga } from 'graphql-yoga'"
    instance.detect("server.tsx", code).should be_true
    instance.detect("server.jsx", code).should be_true
    instance.detect("server.mjs", code).should be_true
    instance.detect("server.cjs", code).should be_true
  end

  it "does not match unrelated frameworks" do
    instance.detect("server.ts", "import express from 'express'").should be_false
  end

  it "does not match non-js files" do
    instance.detect("schema.graphql", "type Query { hello: String }").should be_false
  end
end
