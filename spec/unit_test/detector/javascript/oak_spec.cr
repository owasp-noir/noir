require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Oak" do
  options = create_test_options
  instance = Detector::Javascript::Oak.new options

  it "jsr_import_single_quot" do
    instance.detect("main.ts", "import { Router } from '@oak/oak'").should be_true
  end

  it "jsr_import_double_quot" do
    instance.detect("main.ts", "import { Router } from \"@oak/oak\"").should be_true
  end

  it "jsr_bare_specifier_single_quot" do
    instance.detect("main.ts", "import { Router } from 'jsr:@oak/oak'").should be_true
  end

  it "jsr_bare_specifier_double_quot" do
    instance.detect("main.ts", "import { Router } from \"jsr:@oak/oak\"").should be_true
  end

  it "require_style" do
    instance.detect("main.ts", "const { Router } = require(\"@oak/oak\")").should be_true
  end

  it "deno_land_url_unversioned" do
    instance.detect("main.ts", "import { Router } from \"https://deno.land/x/oak/mod.ts\"").should be_true
  end

  it "deno_land_url_versioned" do
    instance.detect("main.ts", "import { Router } from \"https://deno.land/x/oak@v12.6.1/mod.ts\"").should be_true
  end

  it "deno_land_url_no_protocol" do
    instance.detect("main.ts", "import { Router } from \"deno.land/x/oak/mod.ts\"").should be_true
  end

  it "deno_json_import_map" do
    content = %({"imports": {"@oak/oak": "jsr:@oak/oak@^17.1.0"}})
    instance.detect("deno.json", content).should be_true
  end

  it "deno_jsonc_import_map" do
    content = %({"imports": {"oak/": "https://deno.land/x/oak@v12.6.1/"}})
    instance.detect("deno.jsonc", content).should be_true
  end

  it "import_map_json" do
    content = %({"imports": {"@oak/oak": "jsr:@oak/oak@^17.1.0"}})
    instance.detect("import_map.json", content).should be_true
  end

  it "js_extension" do
    instance.detect("main.js", "import { Router } from \"@oak/oak\";").should be_true
  end

  it "not_oak" do
    instance.detect("main.ts", "import { Router } from 'koa-router'").should be_false
  end

  it "not_oak_deno_land_other_package" do
    instance.detect("main.ts", "import { serve } from \"https://deno.land/std/http/server.ts\"").should be_false
  end

  it "no_signal_no_match" do
    instance.detect("main.ts", "console.log('hello world')").should be_false
  end

  it "package_json_without_signal" do
    instance.detect("package.json", %({"name": "some-app"})).should be_false
  end

  it "unrelated_extension" do
    instance.detect("main.py", "from oak import Router").should be_false
  end
end
