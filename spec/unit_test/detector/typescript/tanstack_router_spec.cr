require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/tanstack_router"

describe "Detect TypeScript TanStack Router" do
  options = create_test_options
  instance = Detector::Typescript::TanstackRouter.new options

  it "import_tanstack_react_router_single_quot" do
    instance.detect("routes.ts", "import { createFileRoute } from '@tanstack/react-router'").should be_true
  end

  it "import_tanstack_react_router_double_quot" do
    instance.detect("routes.ts", "import { createFileRoute } from \"@tanstack/react-router\"").should be_true
  end

  it "import_tanstack_router_single_quot" do
    instance.detect("routes.ts", "import { createRoute } from '@tanstack/router'").should be_true
  end

  it "import_tanstack_router_double_quot" do
    instance.detect("routes.ts", "import { createRoute } from \"@tanstack/router\"").should be_true
  end

  it "require_tanstack_react_router_single_quot" do
    instance.detect("routes.ts", "require('@tanstack/react-router')").should be_true
  end

  it "require_tanstack_react_router_double_quot" do
    instance.detect("routes.ts", "require(\"@tanstack/react-router\")").should be_true
  end

  it "require_tanstack_router_single_quot" do
    instance.detect("routes.ts", "require('@tanstack/router')").should be_true
  end

  it "require_tanstack_router_double_quot" do
    instance.detect("routes.ts", "require(\"@tanstack/router\")").should be_true
  end

  it "createFileRoute" do
    instance.detect("posts.tsx", "export const Route = createFileRoute('/posts')({})").should be_true
  end

  it "createRootRoute" do
    instance.detect("root.tsx", "export const rootRoute = createRootRoute({})").should be_true
  end

  it "createRoute" do
    instance.detect("routes.ts", "const postsRoute = createRoute({ path: '/posts' })").should be_true
  end

  it "createRouter" do
    instance.detect("router.ts", "const router = createRouter({ routeTree })").should be_true
  end

  it "tsx_file" do
    instance.detect("route.tsx", "createFileRoute('/api')").should be_true
  end

  it "should_not_detect_non_tanstack" do
    instance.detect("app.ts", "import express from 'express'").should be_false
  end

  it "should_not_detect_javascript_file" do
    instance.detect("app.js", "import { createFileRoute } from '@tanstack/react-router'").should be_false
  end

  it "should_not_detect_wrong_file_extension" do
    instance.detect("app.py", "createFileRoute('/posts')").should be_false
  end
end
