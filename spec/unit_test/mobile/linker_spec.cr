require "file_utils"
require "../../spec_helper"
require "../../../src/models/logger"
require "../../../src/models/code_locator"
require "../../../src/mobile/linker.cr"

# The linker resolves an Android mobile endpoint's handler component to its
# source file, attaches the handler as a code_path, and pulls 1-hop callees
# from the intent-handling methods.
describe "NoirMobileLinker" do
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android"))
  kt = File.join(base, "src", "main", "java", "com", "example", "myapp", "DeepLinkActivity.kt")
  alias_kt = File.join(base, "src", "main", "java", "com", "example", "myapp", "AliasTargetActivity.kt")
  router_java = File.join(base, "src", "main", "java", "com", "example", "myapp", "RouterActivity.java")

  logger = NoirLogger.new(false, false, false, true)

  # Seed the file_map so ClassIndex#build can find the .kt via files_by_extension.
  locator = CodeLocator.instance
  locator.clear("file_map")
  locator.register_file(kt, File.read(kt))
  locator.register_file(alias_kt, File.read(alias_kt))
  locator.register_file(router_java, File.read(router_java))

  # Endpoint is a struct; mutate locals directly (`.tap` would not persist).
  scheme = Endpoint.new("myapp://complex/:id", "GET")
  scheme.protocol = "mobile-scheme"
  scheme.metadata = {"via" => ".DeepLinkActivity", "package" => "com.example.myapp"}

  bare = Endpoint.new("myapp://accounts/profile", "GET")
  bare.protocol = "mobile-scheme"

  alias_endpoint = Endpoint.new("myapp://alias", "GET")
  alias_endpoint.protocol = "mobile-scheme"
  alias_endpoint.metadata = {"via" => ".AliasTargetActivity", "package" => "com.example.myapp"}

  router_endpoint = Endpoint.new("myapp://router", "GET")
  router_endpoint.protocol = "mobile-scheme"
  router_endpoint.metadata = {"via" => ".RouterActivity", "package" => "com.example.myapp"}

  result = NoirMobileLinker.apply([scheme, bare, alias_endpoint, router_endpoint], logger)
  linked = result[0]
  linked_alias = result[2]
  linked_router = result[3]

  it "adds the handler source file as a code_path" do
    paths = linked.details.code_paths.map { |p| File.basename(p.path) }
    paths.should contain("DeepLinkActivity.kt")
  end

  it "extracts 1-hop callees from the intent handler" do
    names = linked.callees.map(&.name)
    names.should contain("webView.loadUrl")
    names.should contain("renderProfile")
  end

  it "extracts getQueryParameter reads as query params" do
    linked.params.any? { |p| p.name == "redirect" && p.param_type == "query" }.should be_true
    linked.params.any? { |p| p.name == "utm_source" && p.param_type == "query" }.should be_true
  end

  it "extracts get*Extra reads as extra params" do
    linked.params.any? { |p| p.name == "userId" && p.param_type == "extra" }.should be_true
    linked.params.any? { |p| p.name == "verified" && p.param_type == "extra" }.should be_true
  end

  it "leaves an endpoint whose component has no resolvable source untouched" do
    result[1].callees.should be_empty
  end

  it "links activity-alias endpoints to their target activity source" do
    linked_alias.callees.map(&.name).should contain("dispatchAlias")
    linked_alias.params.any? { |p| p.name == "aliasToken" && p.param_type == "extra" }.should be_true
  end

  it "expands Android delegate methods for extra params" do
    names = linked_router.callees.map(&.name)
    names.should contain("getInboundUrl")
    names.should contain("intent.getStringExtra")
    names.should_not contain("getString")
    linked_router.params.any? { |p| p.name == "EXTRA_TEXT" && p.param_type == "extra" }.should be_true
    linked_router.params.any? { |p| p.name == "EXTRA_STREAM" && p.param_type == "extra" }.should be_true
  end

  it "extracts Android params beyond the capped callee list" do
    root = File.tempname("noir-android-many-extras")

    begin
      source_dir = File.join(root, "src", "main", "java", "com", "example", "myapp")
      FileUtils.mkdir_p(source_dir)
      source = String.build do |io|
        io << "package com.example.myapp;\n"
        io << "import android.app.Activity;\n"
        io << "import android.content.Intent;\n"
        io << "import android.os.Bundle;\n"
        io << "class ManyExtrasActivity extends Activity {\n"
        io << "  protected void onCreate(Bundle savedInstanceState) {\n"
        12.times do |idx|
          io << "    Intent intent#{idx} = getIntent();\n"
          io << "    intent#{idx}.getStringExtra(\"extra#{idx}\");\n"
        end
        io << "  }\n"
        io << "}\n"
      end
      path = File.join(source_dir, "ManyExtrasActivity.java")
      File.write(path, source)

      locator.clear("file_map")
      locator.register_file(path, source)

      endpoint = Endpoint.new("myapp://many", "GET")
      endpoint.protocol = "mobile-scheme"
      endpoint.metadata = {"via" => ".ManyExtrasActivity", "package" => "com.example.myapp"}

      linked_many = NoirMobileLinker.apply([endpoint], logger)[0]

      linked_many.params.size.should eq(12)
      linked_many.params.map(&.name).should contain("extra11")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
      locator.clear("file_map")
    end
  end
end

describe "NoirMobileLinker iOS handlers" do
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios"))
  files = [
    File.join(base, "AppDelegate.swift"),
    File.join(base, "AppStateMachine.swift"),
    File.join(base, "SceneDelegate.swift"),
    File.join(base, "LegacyAppDelegate.m"),
    File.join(base, "Tests", "FakeAppDelegateTests.swift"),
  ]

  logger = NoirLogger.new(false, false, false, true)
  locator = CodeLocator.instance
  locator.clear("file_map")
  files.each { |path| locator.register_file(path, File.read(path)) }

  scheme = Endpoint.new("myapp://", "GET")
  scheme.protocol = "mobile-scheme"
  scheme_details = scheme.details
  scheme_details.technology = "ios"
  scheme.details = scheme_details

  universal = Endpoint.new("https://myapp.example.com/", "GET")
  universal.protocol = "universal-link"
  universal_details = universal.details
  universal_details.technology = "ios"
  universal.details = universal_details

  result = NoirMobileLinker.apply([scheme, universal], logger)
  linked_scheme = result[0]
  linked_universal = result[1]

  it "links Swift and Objective-C URL handlers to custom schemes" do
    names = linked_scheme.callees.map(&.name)
    names.should contain("routeOpenURL")
    names.should contain("logOpen")
    names.should contain("handleDeepLink")
    names.should contain("webView?.load")
    names.should contain("openURL")
    names.should contain("coordinator.shouldProcessDeepLink")
    names.should contain("coordinator.handleURL")
    names.should contain("handleObjcDeepLink")
  end

  it "links Swift and Objective-C userActivity handlers to universal links" do
    names = linked_universal.callees.map(&.name)
    names.should contain("routeUniversalLink")
    names.should contain("routeObjcUniversalLink")
  end

  it "extracts query params from Swift and Objective-C URL handlers" do
    linked_scheme.params.any? { |p| p.name == "redirect" && p.param_type == "query" }.should be_true
    linked_scheme.params.any? { |p| p.name == "token" && p.param_type == "query" }.should be_true
  end

  it "skips test-only iOS handlers" do
    linked_scheme.callees.map(&.name).should_not contain("TestOnlyDeepLinkHandler.run")
  end

  it "filters low-signal iOS framework and collection callees" do
    names = linked_scheme.callees.map(&.name)
    names.should_not contain("URL")
    names.should_not contain("URLRequest")
    names.should_not contain("URLComponents")
    names.should_not contain("components?.queryItems?.first")
    names.should_not contain("componentsWithURL")
    names.should_not contain("isEqualToString")
    names.should_not contain("UIApplication.shared.canOpenURL")
    names.should_not contain("NotificationCenter.default.post")
    names.should_not contain("print")
    names.should_not contain("url.host")
  end
end

describe "NoirMobileLinker iOS multi-app scoping" do
  logger = NoirLogger.new(false, false, false, true)

  it "uses a broader generated-project fallback when no Xcode project exists" do
    root = File.tempname("noir-ios-generated-project")
    config_dir = File.join(root, "Config")
    source_dir = File.join(root, "Sources")
    plist = File.join(config_dir, "Info.plist")
    delegate = File.join(source_dir, "AppDelegate.swift")

    begin
      Dir.mkdir_p(config_dir)
      Dir.mkdir_p(source_dir)
      File.write(plist, "")
      File.write(delegate, <<-SWIFT)
        final class AppDelegate {
          func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
            GeneratedProjectRouter.route(url)
            return true
          }
        }
        SWIFT

      locator = CodeLocator.instance
      locator.clear("file_map")
      locator.register_file(delegate, File.read(delegate))

      endpoint = Endpoint.new("generated://", "GET", Details.new(PathInfo.new(plist)))
      endpoint.protocol = "mobile-scheme"
      endpoint_details = endpoint.details
      endpoint_details.technology = "ios"
      endpoint.details = endpoint_details

      linked = NoirMobileLinker.apply([endpoint], logger)
      linked[0].callees.map(&.name).should contain("GeneratedProjectRouter.route")
    ensure
      FileUtils.rm_rf(root) if root
      CodeLocator.instance.clear("file_map")
    end
  end

  it "only follows forwarded action cases for the dispatched action type" do
    root = File.tempname("noir-ios-forwarded-action")
    plist = File.join(root, "Info.plist")
    delegate = File.join(root, "AppDelegate.swift")
    state_machine = File.join(root, "AppStateMachine.swift")
    unrelated = File.join(root, "UnrelatedAction.swift")

    begin
      Dir.mkdir_p(File.join(root, "App.xcodeproj"))
      File.write(File.join(root, "App.xcodeproj", "project.pbxproj"), "")
      File.write(plist, "")
      File.write(delegate, <<-SWIFT)
        final class AppDelegate {
          private let stateMachine: AppStateMachine = AppStateMachine()

          func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
            stateMachine.handle(.openURL(url))
            return true
          }
        }
        SWIFT
      File.write(state_machine, <<-SWIFT)
        enum AppAction {
          case openURL(URL)
        }

        final class AppStateMachine {
          let currentState = ForegroundState()

          func handle(_ action: AppAction) {
            currentState.handle(action: action)
          }
        }

        final class ForegroundState {
          func handle(action: AppAction) {
            switch action {
            case .openURL(let url):
              RealDeepLinkRouter.route(url)
            }
          }
        }
        SWIFT
      File.write(unrelated, <<-SWIFT)
        enum OtherAction {
          case openURL(URL)
        }

        final class OtherState {
          func handle(action: OtherAction) {
            switch action {
            case .openURL(let url):
              UnrelatedRouter.route(url)
            }
          }
        }
        SWIFT

      locator = CodeLocator.instance
      locator.clear("file_map")
      [delegate, state_machine, unrelated].each { |path| locator.register_file(path, File.read(path)) }

      endpoint = Endpoint.new("forwarded://", "GET", Details.new(PathInfo.new(plist)))
      endpoint.protocol = "mobile-scheme"
      endpoint_details = endpoint.details
      endpoint_details.technology = "ios"
      endpoint.details = endpoint_details

      linked = NoirMobileLinker.apply([endpoint], logger)
      names = linked[0].callees.map(&.name)

      names.should contain("stateMachine.handle")
      names.should contain("RealDeepLinkRouter.route")
      names.should_not contain("UnrelatedRouter.route")
    ensure
      FileUtils.rm_rf(root) if root
      CodeLocator.instance.clear("file_map")
    end
  end

  it "does not attach handlers from a sibling iOS app in the same repository" do
    root = File.tempname("noir-ios-multi-app")
    app_a = File.join(root, "AppA")
    app_b = File.join(root, "AppB")
    app_a_delegate = File.join(app_a, "AppDelegate.swift")
    app_b_delegate = File.join(app_b, "AppDelegate.swift")
    app_a_plist = File.join(app_a, "Info.plist")
    app_b_plist = File.join(app_b, "Info.plist")

    begin
      Dir.mkdir_p(File.join(app_a, "AppA.xcodeproj"))
      Dir.mkdir_p(File.join(app_b, "AppB.xcodeproj"))
      File.write(File.join(app_a, "AppA.xcodeproj", "project.pbxproj"), "")
      File.write(File.join(app_b, "AppB.xcodeproj", "project.pbxproj"), "")
      File.write(app_a_plist, "")
      File.write(app_b_plist, "")
      File.write(app_a_delegate, <<-SWIFT)
        final class AppDelegate {
          func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
            AppADeepLinkRouter.route(url)
            return true
          }
        }
        SWIFT
      File.write(app_b_delegate, <<-SWIFT)
        final class AppDelegate {
          func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
            AppBDeepLinkRouter.route(url)
            return true
          }
        }
        SWIFT

      locator = CodeLocator.instance
      locator.clear("file_map")
      locator.register_file(app_a_delegate, File.read(app_a_delegate))
      locator.register_file(app_b_delegate, File.read(app_b_delegate))

      endpoint_a = Endpoint.new("appa://", "GET", Details.new(PathInfo.new(app_a_plist)))
      endpoint_a.protocol = "mobile-scheme"
      endpoint_a_details = endpoint_a.details
      endpoint_a_details.technology = "ios"
      endpoint_a.details = endpoint_a_details

      endpoint_b = Endpoint.new("appb://", "GET", Details.new(PathInfo.new(app_b_plist)))
      endpoint_b.protocol = "mobile-scheme"
      endpoint_b_details = endpoint_b.details
      endpoint_b_details.technology = "ios"
      endpoint_b.details = endpoint_b_details

      linked = NoirMobileLinker.apply([endpoint_a, endpoint_b], logger)
      app_a_callees = linked[0].callees.map(&.name)
      app_b_callees = linked[1].callees.map(&.name)

      app_a_callees.should contain("AppADeepLinkRouter.route")
      app_a_callees.should_not contain("AppBDeepLinkRouter.route")
      app_b_callees.should contain("AppBDeepLinkRouter.route")
      app_b_callees.should_not contain("AppADeepLinkRouter.route")
    ensure
      FileUtils.rm_rf(root) if root
      CodeLocator.instance.clear("file_map")
    end
  end
end
