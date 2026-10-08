require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/*"

describe "Detect TypeScript Wasp" do
  options = create_test_options
  instance = Detector::Typescript::Wasp.new options

  it "main.wasp DSL app" do
    instance.detect("main.wasp", "app todoApp {\n  wasp: { version: \"^0.16.0\" },\n  title: \"ToDo\"\n}").should be_true
  end

  it "main.wasp.ts Wasp Spec" do
    instance.detect("main.wasp.ts", "import { app } from \"@wasp.sh/spec\";\nexport default app({ name: \"x\" });").should be_true
  end

  it "feature *.wasp.ts" do
    instance.detect("src/tasks/tasks.wasp.ts", "import { query, type Spec } from '@wasp.sh/spec';").should be_true
  end

  it "preview wasp-config TS config" do
    instance.detect("main.wasp.ts", "import { App } from 'wasp-config';\nconst app = new App('x', {});").should be_true
  end

  it ".wasproot marker" do
    instance.detect(".wasproot", "File marking the root of Wasp project.").should be_true
  end

  it "a .wasp file that is not an app" do
    instance.detect("notes.wasp", "route RootRoute { path: \"/\", to: MainPage }").should be_false
  end

  it "an app block without the wasp version" do
    instance.detect("config.wasp", "app server {\n  port: 8080\n}").should be_false
  end

  it "a regular .ts file importing the spec package" do
    instance.detect("src/helpers.ts", "import { app } from \"@wasp.sh/spec\";").should be_false
  end

  it "a .wasp.ts file without a Wasp import" do
    instance.detect("demo.wasp.ts", "export const wasp = { version: '1' };").should be_false
  end

  it "generated copies under .wasp/" do
    instance.detect("app/.wasp/out/types/spec/main.wasp.ts", "import { app } from \"@wasp.sh/spec\";").should be_false
  end
end
