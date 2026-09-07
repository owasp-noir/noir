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

  it "import_tanstack_solid_router" do
    instance.detect("routes.ts", "import { createRoute } from '@tanstack/solid-router'").should be_true
  end

  it "ignores the devtools package on its own" do
    instance.detect("app.ts", "import { TanStackRouterDevtools } from '@tanstack/react-router-devtools'").should be_false
  end

  it "createRootRouteWithContext" do
    instance.detect("root.tsx", "const rootRoute = createRootRouteWithContext<Ctx>()({})").should be_true
  end

  it "matches a formatter-wrapped multi-line import" do
    src = <<-TS
      import {
        createRoute,
        createRouter,
      } from '@tanstack/react-router'

      const postsRoute = createRoute({ path: '/posts' })
      TS
    instance.detect("routes.ts", src).should be_true
  end

  it "does not claim Vue Router's createRouter" do
    src = <<-TS
      import { createRouter, createWebHistory } from 'vue-router'

      export default createRouter({
        history: createWebHistory(),
        routes: [{ path: '/', component: Home }],
      })
      TS
    instance.detect("router.ts", src).should be_false
  end

  it "does not claim a tRPC v9 createRouter helper" do
    src = <<-TS
      import * as trpc from '@trpc/server'

      export function createRouter() {
        return trpc.router<Context>()
      }
      TS
    instance.detect("createRouter.ts", src).should be_false
  end

  it "does not claim a bare createRoute call from another router" do
    instance.detect("routes.ts", "const postsRoute = createRoute({ path: '/posts' })").should be_false
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
