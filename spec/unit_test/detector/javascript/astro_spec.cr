require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/astro"

describe "Detect JS Astro" do
  options = create_test_options
  instance = Detector::Javascript::Astro.new options

  it "detects .astro files" do
    instance.applicable?("src/pages/index.astro").should be_true
    instance.detect("src/pages/index.astro", "---
const title = 'Home';
---
<html><body>{title}</body></html>").should be_true
  end

  it "detects astro config files" do
    instance.applicable?("astro.config.mjs").should be_true
    instance.detect("astro.config.mjs", "export default defineConfig({});").should be_true

    instance.applicable?("astro.config.ts").should be_true
    instance.detect("astro.config.ts", "export default defineConfig({});").should be_true

    instance.applicable?("astro.config.js").should be_true
    instance.detect("astro.config.js", "module.exports = {};").should be_true

    instance.applicable?("astro.config.cjs").should be_true
    instance.detect("astro.config.cjs", "module.exports = {};").should be_true
  end

  it "detects package.json with astro dependency" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"astro": "^4.0.0"}})).should be_true
  end

  it "does not detect package.json without astro" do
    instance.detect("package.json", %({"dependencies": {"express": "^4.0.0"}})).should be_false
  end

  it "does not detect unrelated files" do
    instance.detect("app.js", "console.log('hello')").should be_false
    instance.applicable?("app.py").should be_false
  end
end
