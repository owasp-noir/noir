require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/adonisjs"

describe "Detect JS AdonisJS" do
  options = create_test_options
  instance = Detector::Javascript::Adonisjs.new options

  it "detects ace bootstrap file" do
    instance.applicable?("ace").should be_true
    instance.detect("ace", "#!/usr/bin/env node").should be_true

    instance.applicable?("./ace").should be_true
    instance.detect("./ace", "#!/usr/bin/env node").should be_true

    instance.applicable?("bin/ace").should be_true
    instance.detect("bin/ace", "#!/usr/bin/env node").should be_true

    instance.applicable?("ace.js").should be_true
    instance.detect("ace.js", "import './bin/console.js'").should be_true
  end

  it "detects package.json with AdonisJS dependency" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"@adonisjs/core": "^6.0.0"}})).should be_true
    instance.detect("package.json", %({"dependencies": {"adonis-auth": "^3.0.0"}})).should be_true
  end

  it "detects source files with AdonisJS markers" do
    instance.applicable?("start/routes.ts").should be_true
    instance.detect("start/routes.ts", %{import router from '@adonisjs/core/services/router';}).should be_true

    instance.applicable?("start/routes.js").should be_true
    instance.detect("start/routes.js", %{const Route = use('@ioc:Adonis/Core/Route');}).should be_true

    instance.applicable?("start/routes.mjs").should be_true
    instance.detect("start/routes.mjs", %{import router from '@adonisjs/core/services/router';}).should be_true
  end

  it "does not detect package.json without AdonisJS" do
    instance.detect("package.json", %({"dependencies": {"express": "^4.0.0"}})).should be_false
  end

  it "does not detect unrelated source files" do
    instance.detect("app.js", "console.log('hello');").should be_false
    instance.applicable?("app.py").should be_false
  end
end
