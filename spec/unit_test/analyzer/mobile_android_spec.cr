require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/android.cr"

# FunctionalTester only checks url / method / protocol / params, so the
# `metadata` hash, tags, and path-normalization edge cases are asserted here.
describe "Analyzer::Mobile::Android" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android", "AndroidManifest.xml"))

  CodeLocator.instance.clear("android-manifest")
  CodeLocator.instance.push("android-manifest", manifest)
  endpoints = Analyzer::Mobile::Android.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves @string/ scheme references via strings.xml" do
    ep = find.call("myappstr://settings")
    ep.should_not be_nil
    ep.not_nil!.protocol.should eq("mobile-scheme")
  end

  it "resolves @string/ references from any res/values/*.xml file" do
    # alt_scheme lives in donottranslate.xml, not strings.xml.
    find.call("altscheme://alt").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "keeps an unresolvable @string scheme verbatim and tags it unresolved" do
    ep = find.call("@string/missing_scheme://ghost").not_nil!
    ep.tags.any? { |t| t.name == "unresolved" }.should be_true
  end

  it "normalizes templated {id} segments to :id" do
    find.call("myapp://complex/:id").should_not be_nil
  end

  it "uses pathPrefix as a literal path segment" do
    find.call("myapp://accounts/profile").should_not be_nil
  end

  it "marks an autoVerify https filter as a universal-link" do
    ep = find.call("https://myapp.example.com/complex/:id")
    ep.should_not be_nil
    ep.not_nil!.protocol.should eq("universal-link")
  end

  it "attaches the handling component as metadata[\"via\"]" do
    ep = find.call("myapp://complex/:id").not_nil!
    md = ep.metadata.not_nil!
    md["via"].should eq(".DeepLinkActivity")
    md["action"].should eq("android.intent.action.VIEW")
    md["host"].should eq("complex")
    md["package"].should eq("com.example.myapp")
  end

  it "uses activity-alias targetActivity as the linkable handler" do
    ep = find.call("myapp://alias").not_nil!
    md = ep.metadata.not_nil!
    md["via"].should eq(".AliasTargetActivity")
    md["host"].should eq("alias")
  end

  it "does not emit a separate intent:// entry for a deep-link component" do
    find.call("intent://com.example.myapp/.DeepLinkActivity").should be_nil
  end

  it "emits a bare intent:// endpoint for an exported, data-less component" do
    ep = find.call("intent://com.example.myapp/.SyncService").not_nil!
    ep.protocol.should eq("android-intent")
    ep.metadata.not_nil!["action"].should eq("com.example.ACTION_SYNC")
  end

  it "emits an explicit android-intent surface for an exported, filter-less component" do
    ep = find.call("intent://com.example.myapp/.ExportedActivity").not_nil!
    ep.protocol.should eq("android-intent")
    md = ep.metadata.not_nil!
    md["component_type"].should eq("activity")
    md["explicit"].should eq("true")
    md["exported"].should eq("true")
    md["package"].should eq("com.example.myapp")
    # No intent-filter, so no action/category metadata.
    md.has_key?("action").should be_false
  end

  it "records the component kind for filter-less service / receiver surfaces" do
    find.call("intent://com.example.myapp/.ExportedService").not_nil!.metadata.not_nil!["component_type"].should eq("service")
    find.call("intent://com.example.myapp/.ExportedReceiver").not_nil!.metadata.not_nil!["component_type"].should eq("receiver")
  end

  it "carries a guarding android:permission in metadata without suppressing the surface" do
    md = find.call("intent://com.example.myapp/.ExportedReceiver").not_nil!.metadata.not_nil!
    md["permission"].should eq("com.example.permission.CUSTOM")
  end

  it "uses targetActivity as via for a filter-less exported activity-alias" do
    # The alias is addressed by its own name in the URL, but its handler code
    # lives in targetActivity, so `via` points there for the linker.
    ep = find.call("intent://com.example.myapp/.ExportedAlias").not_nil!
    md = ep.metadata.not_nil!
    md["component_type"].should eq("activity-alias")
    md["via"].should eq(".AliasTargetActivity")
    md["explicit"].should eq("true")
  end

  it "does not report a filter-less component that is not exported" do
    find.call("intent://com.example.myapp/.InternalActivity").should be_nil
    find.call("intent://com.example.myapp/.DefaultActivity").should be_nil
  end

  it "does not report an exported component that is explicitly disabled" do
    find.call("intent://com.example.myapp/.DisabledActivity").should be_nil
  end

  it "emits a content:// surface for an exported ContentProvider" do
    ep = find.call("content://com.example.myapp.provider").not_nil!
    ep.protocol.should eq("android-provider")
    md = ep.metadata.not_nil!
    md["component_type"].should eq("provider")
    md["exported"].should eq("true")
    md["package"].should eq("com.example.myapp")
    # The provider class is the handler, surfaced as `via` for the linker.
    md["via"].should eq(".ExportedProvider")
    # No permission declared, so no permission keys.
    md.has_key?("permission").should be_false
    md.has_key?("read_permission").should be_false
  end

  it "records read/write permissions, uri grants, and path-permission flags for a provider" do
    md = find.call("content://com.example.myapp.secret").not_nil!.metadata.not_nil!
    md["read_permission"].should eq("com.example.permission.READ_SECRET")
    md["write_permission"].should eq("com.example.permission.WRITE_SECRET")
    # <grant-uri-permission> child grants ad-hoc URI access.
    md["grant_uri_permissions"].should eq("true")
    # <path-permission> child declares granular per-path rules.
    md["path_permissions"].should eq("true")
  end

  it "emits one provider endpoint per semicolon-separated authority" do
    first = find.call("content://com.example.myapp.first").not_nil!
    second = find.call("content://com.example.myapp.second").not_nil!
    first.protocol.should eq("android-provider")
    second.protocol.should eq("android-provider")
    # grantUriPermissions via the attribute form.
    first.metadata.not_nil!["grant_uri_permissions"].should eq("true")
    second.metadata.not_nil!["grant_uri_permissions"].should eq("true")
  end

  it "does not report a provider that is not exported or default (not-exported)" do
    find.call("content://com.example.myapp.internal").should be_nil
    find.call("content://com.example.myapp.default").should be_nil
  end

  it "does not emit anything for a MAIN/LAUNCHER component" do
    find.call("intent://com.example.myapp/.MainActivity").should be_nil
  end

  it "drops local-content (file/content) and bare-* wildcard-host data filters" do
    find.call("content://*").should be_nil
    find.call("file://*").should be_nil
    find.call("http://*").should be_nil
  end

  it "renders an opaque scheme without a // authority" do
    find.call("mailto:").not_nil!.protocol.should eq("mobile-scheme")
    find.call("mailto://").should be_nil
  end

  it "keeps the // authority on schemes that use one (market://details)" do
    # `market://details?id=…` and streaming `mms://host` are NOT opaque.
    find.call("market://details").not_nil!.protocol.should eq("mobile-scheme")
    find.call("market:").should be_nil
  end

  it "combines scheme and host/path split across separate <data> elements" do
    # SplitLinkActivity declares schemes and host+path in separate <data>
    # children; Android cross-products them, so all four resolve.
    %w[
      http://split.example.com/wiki/ https://split.example.com/wiki/
      http://split.example.com/zh https://split.example.com/zh
    ].each do |url|
      ep = find.call(url).not_nil!
      ep.protocol.should eq("universal-link") # autoVerify + http/https
      ep.metadata.not_nil!["host"].should eq("split.example.com")
      ep.metadata.not_nil!["via"].should eq(".SplitLinkActivity")
    end
  end

  it "does not emit a bare scheme-only endpoint from the split-data filter" do
    # The pre-combining behavior emitted `http://` / `https://` with no host.
    find.call("http://").should be_nil
    find.call("https://").should be_nil
  end

  it "suppresses scheme-only content-handler (mimeType) data entries" do
    # FileImportActivity is a text/xml content handler; its file/content/
    # https scheme-only <data> entries are content-source qualifiers, not
    # deep links, and must not surface as endpoints.
    find.call("file://").should be_nil
    find.call("content://").should be_nil
    endpoints.none? { |e| (e.metadata.try { |m| m["via"]? } || "").includes?("FileImportActivity") }.should be_true
  end

  it "resolves gradle manifestPlaceholders in scheme / host / component name" do
    ep = find.call("myapp://links.example.com").not_nil!
    ep.protocol.should eq("mobile-scheme")
    md = ep.metadata.not_nil!
    md["via"].should eq("com.example.myapp.PlaceholderActivity")
    md["host"].should eq("links.example.com")
    ep.tags.any? { |t| t.name == "unresolved" }.should be_false
  end

  it "prefers the defaultConfig placeholder value over a buildTypes override" do
    find.call("myapp://debug.example.com").should be_nil
  end

  it "keeps an unknown placeholder verbatim and tags it unresolved" do
    ep = find.call("myapp://${missingHost}").not_nil!
    ep.tags.any? { |t| t.name == "unresolved" }.should be_true
  end

  it "emits a Jetpack Navigation deep link with templated args and query params" do
    ep = find.call("myapp://users/:userId").not_nil!
    ep.protocol.should eq("mobile-scheme")
    ep.metadata.not_nil!["via"].should eq("com.example.myapp.ProfileFragment")
    ep.metadata.not_nil!["action"].should eq("android.intent.action.VIEW")
    ep.params.any? { |p| p.name == "ref" && p.param_type == "query" }.should be_true
    # The endpoint's file evidence points at the navigation graph itself.
    ep.details.code_paths.any?(&.path.ends_with?("nav_graph.xml")).should be_true
  end

  it "implies https for a scheme-less Navigation URI and strips the .* wildcard" do
    ep = find.call("https://nav.example.com/search/").not_nil!
    ep.protocol.should eq("mobile-scheme")
    ep.metadata.not_nil!["via"].should eq("com.example.myapp.SearchFragment")
    ep.metadata.not_nil!["host"].should eq("nav.example.com")
  end

  it "walks nested <navigation> graphs and resolves ${applicationId} in fragment names" do
    ep = find.call("myapp://settings/notifications").not_nil!
    ep.metadata.not_nil!["via"].should eq("com.example.myapp.NotificationsFragment")
  end
end

# Kotlin-DSL gradle (build.gradle.kts found by walking up from the manifest)
# and a manifest without a `package` attribute.
describe "Analyzer::Mobile::Android (gradle kts / package fallback)" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android_kts",
      "app", "src", "main", "AndroidManifest.xml"))

  CodeLocator.instance.clear("android-manifest")
  CodeLocator.instance.push("android-manifest", manifest)
  endpoints = Analyzer::Mobile::Android.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves kts indexed / mapOf manifestPlaceholders and ${applicationId} names" do
    ep = find.call("ktsauth://auth.example.com/callback").not_nil!
    md = ep.metadata.not_nil!
    md["via"].should eq("com.example.ktsapp.AuthActivity")
    md["package"].should eq("com.example.ktsapp")
  end

  it "resolves placeholders declared via manifestPlaceholders.put(...)" do
    find.call("ktslegacy://legacy").should_not be_nil
  end

  it "falls back to the gradle applicationId when the manifest has no package" do
    ep = find.call("intent://com.example.ktsapp/.KtsService").not_nil!
    ep.protocol.should eq("android-intent")
  end

  it "resolves ${applicationId} used as a Navigation deep-link scheme" do
    ep = find.call("com.example.ktsapp://oauth/callback").not_nil!
    ep.protocol.should eq("mobile-scheme")
    ep.metadata.not_nil!["via"].should eq("com.example.ktsapp.LoginFragment")
  end
end

# applicationId declared as a constant reference (`applicationId = APP_ID`)
# whose literal lives in a sibling buildSrc/ source tree (the NewPipe shape).
describe "Analyzer::Mobile::Android (gradle constant reference)" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android_gradle_const",
      "app", "src", "main", "AndroidManifest.xml"))

  CodeLocator.instance.clear("android-manifest")
  CodeLocator.instance.push("android-manifest", manifest)
  endpoints = Analyzer::Mobile::Android.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves a constant-referenced applicationId from buildSrc into ${applicationId}" do
    ep = find.call("constapp://com.example.constapp").not_nil!
    ep.protocol.should eq("mobile-scheme")
    ep.tags.any? { |t| t.name == "unresolved" }.should be_false
  end

  it "uses the resolved applicationId as the intent:// package (no empty intent:///)" do
    find.call("intent:///.ConstService").should be_nil
    find.call("intent://com.example.constapp/.ConstService").not_nil!.protocol.should eq("android-intent")
  end
end

# applicationId built from a groovy GString (`applicationId "${appPkg}"`)
# whose `def appPkg = "..."` lives in the same script (the Aegis shape).
describe "Analyzer::Mobile::Android (gradle GString applicationId)" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android_gradle_gstring",
      "AndroidManifest.xml"))

  CodeLocator.instance.clear("android-manifest")
  CodeLocator.instance.push("android-manifest", manifest)
  endpoints = Analyzer::Mobile::Android.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves a GString applicationId into ${applicationId}" do
    ep = find.call("gstringscheme://com.example.gstringapp").not_nil!
    ep.protocol.should eq("mobile-scheme")
    ep.tags.any? { |t| t.name == "unresolved" }.should be_false
  end

  it "uses the GString-resolved applicationId as the intent:// package" do
    find.call("intent:///.GStringService").should be_nil
    find.call("intent://com.example.gstringapp/.GStringService").not_nil!.protocol.should eq("android-intent")
  end
end
