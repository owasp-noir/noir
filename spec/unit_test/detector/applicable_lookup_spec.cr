require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/detector"

describe "Noir::Detection.path_sensitive?" do
  registry = build_detector_list(create_test_options).index_by(&.name)

  it "flags Supabase (migrations / supabase/ path gates)" do
    Noir::Detection.path_sensitive?(registry["supabase"]).should be_true
  end

  it "flags Grails (grails-app path gate)" do
    Noir::Detection.path_sensitive?(registry["groovy_grails"]).should be_true
  end

  it "flags Vercel (root-placed vercel.json)" do
    Noir::Detection.path_sensitive?(registry["vercel"]).should be_true
  end

  it "does not flag extension-only Spring detector" do
    Noir::Detection.path_sensitive?(registry["java_spring"]).should be_false
  end
end

describe "Noir::Detection.build_applicable_lookup" do
  registry = build_detector_list(create_test_options).index_by(&.name)

  it "includes Supabase for a migration path but not a bare .sql basename probe" do
    supabase = registry["supabase"]
    spring = registry["java_spring"]
    detectors = [supabase.as(Detector), spring.as(Detector)]
    lookup = Noir::Detection.build_applicable_lookup(detectors)

    migration = "proj/supabase/migrations/001_init.sql"
    idxs = lookup.call(migration)
    idxs.should contain(0) # supabase

    # Bare basename with no supabase path must not match supabase
    supabase.applicable?("001_init.sql").should be_false
  end

  it "includes Grails for a grails-app path via path-sensitive recheck" do
    grails = registry["groovy_grails"]
    detectors = [grails.as(Detector)]
    lookup = Noir::Detection.build_applicable_lookup(detectors)

    path = "app/grails-app/controllers/Foo.groovy"
    lookup.call(path).should contain(0)
  end
end
