require "spec"
require "../../../src/miniparsers/react_router_config_extractor_ts"

private def rr_routes(source : String) : Array(Tuple(String, String, Int32))
  Noir::TreeSitterReactRouterConfigExtractor.extract(source).routes.map { |r| {r.path, r.file, r.line} }
end

describe Noir::TreeSitterReactRouterConfigExtractor do
  it "reads the helper calls of a typed routes.ts" do
    source = <<-TS
      import {
        type RouteConfig,
        route,
        index,
        layout,
        prefix,
      } from "@react-router/dev/routes";

      export default [
        index("routes/home.tsx"),
        route("about", "routes/about.tsx"),
        layout("routes/auth/layout.tsx", [
          route("login", 'routes/auth/login.tsx'),
        ]),
        ...prefix("concerts", [
          index("routes/concerts/home.tsx"),
          route(":city", "routes/concerts/city.tsx", { id: "city" }, [
            route("*", "routes/concerts/splat.tsx"),
            route("", "routes/concerts/same.tsx"),
          ]),
          route("/concerts/trending", "routes/concerts/trending.tsx"),
        ]),
      ] satisfies RouteConfig;
      TS

    rr_routes(source).should eq([
      {"/", "routes/home.tsx", 10},
      {"/about", "routes/about.tsx", 11},
      {"/login", "routes/auth/login.tsx", 13},
      {"/concerts", "routes/concerts/home.tsx", 16},
      {"/concerts/:city", "routes/concerts/city.tsx", 17},
      {"/concerts/:city/*", "routes/concerts/splat.tsx", 18},
      {"/concerts/:city", "routes/concerts/same.tsx", 19},
      {"/concerts/trending", "routes/concerts/trending.tsx", 21},
    ])
  end

  it "flags flatRoutes() and keeps the routes beside it" do
    source = <<-TS
      import { type RouteConfig, route } from "@react-router/dev/routes";
      import { flatRoutes } from "@react-router/fs-routes";

      export default [
        route("legacy", "legacy.tsx"),
        ...(await flatRoutes()),
      ] satisfies RouteConfig;
      TS

    config = Noir::TreeSitterReactRouterConfigExtractor.extract(source)
    config.flat_routes?.should be_true
    config.routes.map(&.path).should eq(["/legacy"])
  end

  it "reads a config bound to a variable before export" do
    source = <<-JS
      import { route } from "@react-router/dev/routes";
      const routes = [route("users/:id", "routes/user.jsx")];
      export default routes;
      JS

    rr_routes(source).should eq([{"/users/:id", "routes/user.jsx", 2}])
    Noir::TreeSitterReactRouterConfigExtractor.extract(source).flat_routes?.should be_false
  end

  it "skips calls whose path or file is not a string literal" do
    source = <<-TS
      export default [route(PATH, "routes/x.tsx"), index(file)] satisfies RouteConfig;
      TS

    rr_routes(source).should be_empty
  end
end
