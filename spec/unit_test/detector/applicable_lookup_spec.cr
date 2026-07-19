require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/detector/detectors/specification/supabase"
require "../../../src/detector/detectors/groovy/grails"
require "../../../src/detector/detectors/specification/vercel"
require "../../../src/detector/detectors/java/spring"
require "../../../src/models/detector"

describe "detector_path_sensitive?" do
  options = create_test_options

  it "flags Supabase (migrations / supabase/ path gates)" do
    detector_path_sensitive?(Detector::Specification::Supabase.new(options)).should be_true
  end

  it "flags Grails (grails-app path gate)" do
    detector_path_sensitive?(Detector::Groovy::Grails.new(options)).should be_true
  end

  it "flags Vercel (root-placed vercel.json)" do
    detector_path_sensitive?(Detector::Specification::Vercel.new(options)).should be_true
  end

  it "does not flag extension-only Spring detector" do
    detector_path_sensitive?(Detector::Java::Spring.new(options)).should be_false
  end
end

describe "detector_build_applicable_lookup" do
  options = create_test_options

  it "includes Supabase for a migration path but not a bare .sql basename probe" do
    supabase = Detector::Specification::Supabase.new(options)
    spring = Detector::Java::Spring.new(options)
    # set_name is required for detector identity in some paths
    supabase.set_name
    spring.set_name
    detectors = [supabase.as(Detector), spring.as(Detector)]
    lookup = detector_build_applicable_lookup(detectors)

    migration = "proj/supabase/migrations/001_init.sql"
    idxs = lookup.call(migration)
    idxs.should contain(0) # supabase

    # Bare basename with no supabase path must not match supabase
    supabase.applicable?("001_init.sql").should be_false
  end

  it "includes Grails for a grails-app path via path-sensitive recheck" do
    grails = Detector::Groovy::Grails.new(options)
    grails.set_name
    detectors = [grails.as(Detector)]
    lookup = detector_build_applicable_lookup(detectors)

    path = "app/grails-app/controllers/Foo.groovy"
    lookup.call(path).should contain(0)
  end
end
