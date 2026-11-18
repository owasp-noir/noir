require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/models/locator_keys"
require "../../../src/analyzer/analyzers/mobile/android.cr"

# FunctionalTester only checks url / method / protocol / params, so the
# `metadata` hash, tags, and path-normalization edge cases are asserted here.
describe "Analyzer::Mobile::Android" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android", "AndroidManifest.xml"))

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
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

  it "preserves every action and category from a multi-entry intent-filter" do
    md = find.call("intent://com.example.myapp/.SyncService").not_nil!.metadata.not_nil!
    md["action"].should eq("com.example.ACTION_SYNC")
    md["actions"].should eq("com.example.ACTION_SYNC, com.example.ACTION_REFRESH, com.example.ACTION_CANCEL")
    md["category"].should eq("android.intent.category.DEFAULT")
    md["categories"].should eq("android.intent.category.DEFAULT, com.example.category.BACKGROUND")
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

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
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

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
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

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
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

# A filter with thousands of hosts and paths used to build the full
# scheme x host x path product (and dedup with Array#includes?) before
# applying the cap: seconds and GBs for one manifest.
describe "Analyzer::Mobile::Android (huge intent-filter)" do
  it "caps without materialising the full product" do
    dir = File.tempname("noir-android-huge-filter")
    Dir.mkdir_p(dir)
    manifest = File.join(dir, "AndroidManifest.xml")
    hosts = (0...3000).map { |i| %(<data android:host="h#{i}.example.com"/>) }.join("\n")
    paths = (0...3000).map { |i| %(<data android:pathPrefix="/p#{i}"/>) }.join("\n")
    File.write(manifest, <<-XML)
      <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.x">
      <application><activity android:name=".Main" android:exported="true"><intent-filter>
      <action android:name="android.intent.action.VIEW"/>
      <category android:name="android.intent.category.BROWSABLE"/>
      <data android:scheme="https"/><data android:scheme="http"/>
      #{hosts}
      #{paths}
      </intent-filter></activity></application></manifest>
      XML

    CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
    CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
    endpoints = [] of Endpoint
    elapsed = Time.measure { endpoints = Analyzer::Mobile::Android.new(create_test_options).analyze }

    endpoints.size.should eq(Analyzer::Mobile::Android::MAX_FILTER_COMBOS)
    endpoints.first.url.should eq("https://h0.example.com")
    elapsed.should be < 3.seconds
  ensure
    CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
    FileUtils.rm_rf(dir) if dir
  end
end

# A pre-31 manifest may omit `android:exported` on a filter-bearing
# component, and Android then exports it. The <data> branch already read it
# that way; the action-only branch demanded an explicit "true" and dropped
# the receiver.
describe "Analyzer::Mobile::Android (legacy manifest)" do
  dir = File.tempname("noir-android-legacy")
  Dir.mkdir_p(dir)
  manifest = File.join(dir, "AndroidManifest.xml")
  File.write(manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.ex.legacy">
      <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="28"/>
      <application>
        <receiver android:name=".CmdReceiver">
          <intent-filter><action android:name="com.ex.legacy.RUN_COMMAND"/></intent-filter>
        </receiver>
        <activity android:name=".PortActivity" android:exported="true">
          <intent-filter android:autoVerify="true">
            <action android:name="android.intent.action.VIEW"/>
            <category android:name="android.intent.category.BROWSABLE"/>
            <data android:scheme="https" android:host="ex.com" android:port="8443" android:path="/x"/>
          </intent-filter>
        </activity>
        <receiver android:name=".Hidden" android:exported="false">
          <intent-filter><action android:name="com.ex.legacy.HIDDEN"/></intent-filter>
        </receiver>
      </application>
    </manifest>
    XML

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
  urls = Analyzer::Mobile::Android.new(create_test_options).analyze.map(&.url)
  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  FileUtils.rm_rf(dir)

  it "reports an action-only component with no exported attribute" do
    urls.should contain("intent://com.ex.legacy/.CmdReceiver")
  end

  it "keeps android:port in the deep-link authority" do
    urls.should contain("https://ex.com:8443/x")
  end

  it "still drops one that is explicitly not exported" do
    urls.should_not contain("intent://com.ex.legacy/.Hidden")
  end
end

describe "Analyzer::Mobile::Android (filter-bearing component metadata)" do
  dir = File.tempname("noir-android-filtered")
  Dir.mkdir_p(dir)
  manifest = File.join(dir, "AndroidManifest.xml")
  File.write(manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.ex.filtered">
      <application>
        <service android:name=".SyncService" android:exported="true"
                 android:permission="com.ex.filtered.permission.SYNC">
          <intent-filter><action android:name="com.ex.filtered.SYNC"/></intent-filter>
        </service>
        <receiver android:name=".PingReceiver" android:exported="true">
          <intent-filter><action android:name="com.ex.filtered.PING"/></intent-filter>
        </receiver>
        <activity android:name=".LinkActivity" android:exported="true"
                  android:permission="com.ex.filtered.permission.OPEN">
          <intent-filter>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="filtered" android:host="open"/>
          </intent-filter>
        </activity>
      </application>
    </manifest>
    XML

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, manifest)
  endpoints = Analyzer::Mobile::Android.new(create_test_options).analyze
  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  FileUtils.rm_rf(dir)

  metadata = ->(url : String) { endpoints.find! { |e| e.url == url }.metadata.not_nil! }

  it "records the component kind of a service / receiver with an intent-filter" do
    metadata.call("intent://com.ex.filtered/.SyncService")["component_type"].should eq("service")
    metadata.call("intent://com.ex.filtered/.PingReceiver")["component_type"].should eq("receiver")
  end

  it "records the guarding android:permission of a component with an intent-filter" do
    metadata.call("intent://com.ex.filtered/.SyncService")["permission"].should eq("com.ex.filtered.permission.SYNC")
    metadata.call("filtered://open")["permission"].should eq("com.ex.filtered.permission.OPEN")
    metadata.call("intent://com.ex.filtered/.PingReceiver").has_key?("permission").should be_false
  end
end

# A flavor source set re-declares a component only to merge attributes into
# src/main; the overlay stub carries no intent-filter of its own.
describe "Analyzer::Mobile::Android (source-set overlay manifest)" do
  dir = File.tempname("noir-android-overlay")
  main_manifest = File.join(dir, "app", "src", "main", "AndroidManifest.xml")
  beta_manifest = File.join(dir, "app", "src", "beta", "AndroidManifest.xml")
  Dir.mkdir_p(File.dirname(main_manifest))
  Dir.mkdir_p(File.dirname(beta_manifest))
  File.write(main_manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.ex.overlay">
      <application>
        <activity android:name=".EntryActivity" android:exported="true">
          <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
          </intent-filter>
        </activity>
        <activity android:name=".ShareActivity" android:exported="true">
          <intent-filter>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="overlay" android:host="share"/>
          </intent-filter>
        </activity>
      </application>
    </manifest>
    XML
  File.write(beta_manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android"
              xmlns:tools="http://schemas.android.com/tools" package="com.ex.overlay">
      <application>
        <activity android:name=".EntryActivity" android:exported="true" android:screenOrientation="portrait"/>
        <activity android:name=".ShareActivity" android:exported="true" tools:node="replace"/>
        <activity android:name=".BetaOnlyActivity" android:exported="true"/>
      </application>
    </manifest>
    XML

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, main_manifest)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, beta_manifest)
  urls = Analyzer::Mobile::Android.new(create_test_options).analyze.map(&.url)
  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  FileUtils.rm_rf(dir)

  it "does not report an overlay stub of a filter-bearing main component as filter-less" do
    urls.should_not contain("intent://com.ex.overlay/.EntryActivity")
  end

  it "still reports a filter-less component the overlay declares on its own" do
    urls.should contain("intent://com.ex.overlay/.BetaOnlyActivity")
  end

  it "reports a component the overlay replaces without its filters" do
    urls.should contain("intent://com.ex.overlay/.ShareActivity")
  end
end

# A library module has only a namespace; the manifest merger folds its
# components into the consuming application, whose applicationId is the
# package the merged components live in.
describe "Analyzer::Mobile::Android (library module)" do
  dir = File.tempname("noir-android-library")
  app_manifest = File.join(dir, "app", "src", "main", "AndroidManifest.xml")
  lib_manifest = File.join(dir, "lib", "src", "main", "AndroidManifest.xml")
  Dir.mkdir_p(File.dirname(app_manifest))
  Dir.mkdir_p(File.dirname(lib_manifest))
  File.write(File.join(dir, "settings.gradle.kts"), %(include(":app", ":lib")\n))
  File.write(File.join(dir, "app", "build.gradle.kts"), <<-KTS)
    plugins { id("com.android.application") }
    android {
        namespace = "com.example.app"
        defaultConfig { applicationId = "com.example.app" }
    }
    dependencies { implementation(project(":lib")) }
    KTS
  File.write(File.join(dir, "lib", "build.gradle.kts"), <<-KTS)
    plugins { alias(libs.plugins.demo.feature) }
    android { namespace = "com.example.lib" }
    KTS
  File.write(app_manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
      <application>
        <activity android:name=".AppOnlyActivity" android:exported="true"/>
      </application>
    </manifest>
    XML
  File.write(lib_manifest, <<-XML)
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
      <application>
        <activity android:name=".LibLinkActivity" android:exported="true">
          <intent-filter>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="demo" android:host="lib"/>
          </intent-filter>
        </activity>
        <activity android:name=".LibExplicitActivity" android:exported="true"/>
        <provider android:name=".LibFilesProvider" android:exported="true"
                  android:authorities="${applicationId}.files"/>
      </application>
    </manifest>
    XML

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, app_manifest)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, lib_manifest)
  endpoints = Analyzer::Mobile::Android.new(create_test_options).analyze
  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  FileUtils.rm_rf(dir)

  urls = endpoints.map(&.url)

  it "puts library deep links in the consuming application's package" do
    metadata = endpoints.find! { |e| e.url == "demo://lib" }.metadata.not_nil!
    metadata["package"].should eq("com.example.app")
    metadata["via"].should eq("com.example.lib.LibLinkActivity")
  end

  it "names library components by their fully qualified class in the application package" do
    urls.should contain("intent://com.example.app/com.example.lib.LibExplicitActivity")
    urls.should_not contain("intent://com.example.lib/.LibExplicitActivity")
  end

  it "resolves ${applicationId} in a library manifest to the application id" do
    urls.should contain("content://com.example.app.files")
  end

  it "leaves the application module's own components unchanged" do
    urls.should contain("intent://com.example.app/.AppOnlyActivity")
  end
end

# Two applications in one build: a library goes to the one that names it.
# In another build, an application whose id the scan cannot read is not a
# library of that build's only readable application.
describe "Analyzer::Mobile::Android (library module with several applications)" do
  dir = File.tempname("noir-android-library-apps")
  write = ->(path : String, content : String) do
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
  app_script = ->(id : String, deps : String) do
    %(plugins { id("com.android.application") }\nandroid { defaultConfig { applicationId = "#{id}" } }\n#{deps}\n)
  end
  manifest = ->(activity : String) do
    <<-XML
      <manifest xmlns:android="http://schemas.android.com/apk/res/android">
        <application>
          <activity android:name="#{activity}" android:exported="true"/>
        </application>
      </manifest>
      XML
  end

  lib_manifest = File.join(dir, "one", "lib", "src", "main", "AndroidManifest.xml")
  legacy_manifest = File.join(dir, "two", "legacy", "src", "main", "AndroidManifest.xml")
  write.call(File.join(dir, "one", "settings.gradle.kts"), %(include(":app", ":sample", ":lib")\n))
  write.call(File.join(dir, "one", "app", "build.gradle.kts"), app_script.call("com.example.app", %(dependencies { implementation(project(":lib")) })))
  write.call(File.join(dir, "one", "sample", "build.gradle.kts"), app_script.call("com.example.sample", ""))
  write.call(File.join(dir, "one", "lib", "build.gradle.kts"), %(android { namespace = "com.example.lib" }\n))
  write.call(lib_manifest, manifest.call(".LibExplicitActivity"))
  write.call(File.join(dir, "two", "settings.gradle.kts"), %(include(":legacy", ":demo")\n))
  write.call(File.join(dir, "two", "demo", "build.gradle.kts"), app_script.call("com.example.demo", ""))
  write.call(File.join(dir, "two", "legacy", "build.gradle.kts"), <<-KTS)
    plugins { alias(libs.plugins.demo.app) }
    android {
        namespace = "com.example.legacy"
        defaultConfig { applicationId = legacyAppId }
    }
    KTS
  write.call(legacy_manifest, manifest.call(".LegacyActivity"))

  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, lib_manifest)
  CodeLocator.instance.push(Noir::LocatorKeys::ANDROID_MANIFEST, legacy_manifest)
  urls = Analyzer::Mobile::Android.new(create_test_options).analyze.map(&.url)
  CodeLocator.instance.clear(Noir::LocatorKeys::ANDROID_MANIFEST)
  FileUtils.rm_rf(dir)

  it "puts a library in the application whose build script names it" do
    urls.should contain("intent://com.example.app/com.example.lib.LibExplicitActivity")
  end

  it "keeps an application with an unreadable applicationId in its own namespace" do
    urls.should contain("intent://com.example.legacy/.LegacyActivity")
    urls.should_not contain("intent://com.example.demo/com.example.legacy.LegacyActivity")
  end
end
