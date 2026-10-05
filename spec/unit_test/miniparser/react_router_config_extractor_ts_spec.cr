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
          route("/trending", "routes/concerts/trending.tsx"),
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
      # `prefix()` absorbs a child's leading `/` (`joinRoutePaths`).
      {"/concerts/trending", "routes/concerts/trending.tsx", 21},
    ])
  end

  it "keeps an absolute route() child as written" do
    source = <<-TS
      export default [
        route("users", "routes/users.tsx", [route("/users/:id", "routes/user.tsx")]),
      ];
      TS

    rr_routes(source).map(&.[0]).should eq(["/users", "/users/:id"])
  end

  it "follows arrays bound to a name and ignores ones never exported" do
    source = <<-TS
      const api = [route("users", "routes/api/users.ts")];
      export const legacy = [route("old", "routes/old.tsx")];
      // ...(await flatRoutes()),
      export default [index("routes/home.tsx"), ...prefix("api", api)] satisfies RouteConfig;
      TS

    config = Noir::TreeSitterReactRouterConfigExtractor.extract(source)
    config.routes.map(&.path).should eq(["/", "/api/users"])
    config.flat_routes?.should be_false
  end

  it "reads a type-annotated binding exported by name" do
    source = <<-TS
      const routes: RouteConfig = [index("pages/splash.tsx"), route("/brand", "pages/brand.tsx")];
      if (process.env.NODE_ENV === "development") {
        routes.push(route("/__playground", "pages/playground.tsx"));
      }
      export default routes;
      TS

    rr_routes(source).map(&.[0]).should eq(["/", "/brand"])
  end

  it "reads template-literal paths and defineRoutes callbacks" do
    source = <<-TS
      export default remixRoutesOptionAdapter((defineRoutes) =>
        defineRoutes((route) => {
          route(`about`, "routes/about.tsx", () => {
            route(":id", "routes/member.tsx");
          });
          route(`team/${slug}`, "routes/team.tsx");
        })
      );
      TS

    rr_routes(source).map(&.[0]).should eq(["/about", "/about/:id"])
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
