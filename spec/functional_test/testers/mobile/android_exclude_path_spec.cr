require "../../func_spec.cr"

# The Android analyzer walks three directories itself — `res/navigation`
# (deep-link graphs), `res/values` (string resources the manifest
# references) and a sibling `buildSrc` tree (gradle constants) — because
# each is addressed by its role in the project layout. None of them applied
# `--exclude-path`, so an excluded resource still shaped the report: its
# deep links were emitted, and its values still resolved manifest
# placeholders.
empty_count = Hash(Symbol, Int32).new
no_endpoints = [] of Endpoint

res_overrides = Hash(String, YAML::Any).new
res_overrides["exclude_path"] = YAML::Any.new("donottranslate.xml,nav_graph.xml")

buildsrc_overrides = Hash(String, YAML::Any).new
buildsrc_overrides["exclude_path"] = YAML::Any.new("Constants.kt")

baseline = FunctionalTester.new("fixtures/mobile/android/", empty_count, no_endpoints)
res_excluded = FunctionalTester.new("fixtures/mobile/android/", empty_count, no_endpoints, res_overrides)
buildsrc_baseline = FunctionalTester.new("fixtures/mobile/android_gradle_const/", empty_count, no_endpoints)
buildsrc_excluded = FunctionalTester.new("fixtures/mobile/android_gradle_const/",
  empty_count, no_endpoints, buildsrc_overrides)

describe "Android resource walks with --exclude-path" do
  it "reads navigation graphs and every values file by default" do
    urls = baseline.endpoints.map(&.url)
    urls.should contain("myapp://users/:userId") # res/navigation/nav_graph.xml
    urls.should contain("altscheme://alt")       # res/values/donottranslate.xml
    urls.should contain("myappstr://settings")   # res/values/strings.xml
  end

  it "drops an excluded navigation graph and stops resolving an excluded values file" do
    urls = res_excluded.endpoints.map(&.url)
    urls.should_not contain("myapp://users/:userId")
    urls.should_not contain("myapp://settings/notifications")
    urls.should_not contain("altscheme://alt")
    # The scheme is now unresolvable, so it is kept verbatim rather than
    # silently disappearing — and strings.xml still resolves.
    urls.should contain("@string/alt_scheme://alt")
    urls.should contain("myappstr://settings")
  end

  it "resolves a gradle constant from buildSrc by default" do
    buildsrc_baseline.endpoints.map(&.url).should contain("constapp://com.example.constapp")
  end

  it "leaves the placeholder unresolved when buildSrc source is excluded" do
    urls = buildsrc_excluded.endpoints.map(&.url)
    urls.should_not contain("constapp://com.example.constapp")
    urls.should contain("constapp://${applicationId}")
  end
end
