require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/react_router"

describe "Detect JS React Router" do
  options = create_test_options
  instance = Detector::Javascript::ReactRouter.new options

  it "detects package.json with @react-router/dev" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"devDependencies": {"@react-router/dev": "^7.9.0"}})).should be_true
  end

  it "detects react-router.config.*" do
    instance.applicable?("react-router.config.ts").should be_true
    instance.detect("react-router.config.ts", "export default { ssr: true };").should be_true
  end

  it "detects the route config and the vite plugin" do
    instance.detect("app/routes.ts", %(import { type RouteConfig, index } from "@react-router/dev/routes";)).should be_true
    instance.detect("vite.config.ts", %(import { reactRouter } from "@react-router/dev/vite";)).should be_true
  end

  it "does not detect library-mode react-router" do
    instance.detect("package.json", %({"dependencies": {"react-router": "^7.9.0", "react-router-dom": "^7.9.0"}})).should be_false
    instance.detect("src/main.tsx", %(import { createBrowserRouter } from "react-router";)).should be_false
  end

  it "does not detect Remix" do
    instance.detect("package.json", %({"dependencies": {"@remix-run/node": "^2.0.0"}})).should be_false
  end
end
