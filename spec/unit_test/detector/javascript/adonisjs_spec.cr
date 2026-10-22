require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/adonisjs"

describe "Detect JS AdonisJS" do
  options = create_test_options
  instance = Detector::Javascript::Adonisjs.new options

  it "detects ace bootstrap file with AdonisJS markers" do
    adonis_v5_ace = <<-ACE
      #!/usr/bin/env node
      const { Ignitor } = require('@adonisjs/core/build/standalone')
      new Ignitor(__dirname).ace().handle(process.argv.slice(2))
      ACE

    adonis_v6_ace = <<-ACE
      import 'reflect-metadata'
      import { Ignitor, prettyPrintError } from '@adonisjs/core'
      const APP_ROOT = new URL('./', import.meta.url)
      new Ignitor(APP_ROOT).ace().handle(process.argv.splice(2))
      ACE

    instance.applicable?("ace").should be_true
    instance.detect("ace", adonis_v5_ace).should be_true

    instance.applicable?("./ace").should be_true
    instance.detect("./ace", adonis_v5_ace).should be_true

    instance.applicable?("bin/ace").should be_true
    instance.detect("bin/ace", adonis_v5_ace).should be_true

    instance.applicable?("ace.js").should be_true
    instance.detect("ace.js", adonis_v6_ace).should be_true
  end

  it "does not detect vendored ace editor ace.js" do
    vendored_ace_editor = <<-ACE
      define("ace/ace", ["require", "exports", "module"], function(require, exports, module) {
        "use strict";
        var ace = exports;
        ace.edit = function(el) { return new Editor(el); };
      });
      ACE

    instance.applicable?("ace.js").should be_true
    instance.detect("ace.js", vendored_ace_editor).should be_false
    instance.detect("public/js/ace.js", vendored_ace_editor).should be_false
    instance.detect("vendor/ace/ace.js", "/** Ace Editor v1.4.12 */ window.ace = {};").should be_false
  end

  it "detects package.json with AdonisJS dependency" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"@adonisjs/core": "^6.0.0"}})).should be_true
    instance.detect("package.json", %({"dependencies": {"adonis-auth": "^3.0.0"}})).should be_true
  end

  it "detects source files with AdonisJS markers" do
    instance.applicable?("start/routes.ts").should be_true
    instance.detect("start/routes.ts", %(import router from '@adonisjs/core/services/router';)).should be_true

    instance.applicable?("start/routes.js").should be_true
    instance.detect("start/routes.js", %(const Route = use('@ioc:Adonis/Core/Route');)).should be_true

    instance.applicable?("start/routes.mjs").should be_true
    instance.detect("start/routes.mjs", %(import router from '@adonisjs/core/services/router';)).should be_true
  end

  it "does not detect package.json without AdonisJS" do
    instance.detect("package.json", %({"dependencies": {"express": "^4.0.0"}})).should be_false
  end

  it "does not detect unrelated source files" do
    instance.detect("app.js", "console.log('hello');").should be_false
    instance.applicable?("app.py").should be_false
  end
end
