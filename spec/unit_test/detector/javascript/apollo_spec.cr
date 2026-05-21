require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Apollo" do
  options = create_test_options
  instance = Detector::Javascript::Apollo.new options

  it "v4 scoped import" do
    instance.detect("server.ts", "import { ApolloServer } from '@apollo/server'").should be_true
  end

  it "v4 standalone subpath import" do
    instance.detect("server.ts",
      "import { startStandaloneServer } from '@apollo/server/standalone'").should be_true
  end

  it "legacy apollo-server import" do
    instance.detect("server.js", "import { ApolloServer } from 'apollo-server'").should be_true
  end

  it "legacy apollo-server-express import" do
    instance.detect("server.js",
      "const { ApolloServer } = require('apollo-server-express')").should be_true
  end

  it "ApolloServer constructor without explicit import" do
    instance.detect("server.ts", "const server = new ApolloServer({ typeDefs, resolvers });").should be_true
  end

  it "ts/tsx/jsx/mjs/cjs are applicable" do
    code = "import { ApolloServer } from '@apollo/server'"
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
