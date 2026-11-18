require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# Code-level deep-link route harvesting: Info.plist only ever declares the
# bare `scheme://`, so real routes (`scheme://host`, full literal URLs) have
# to be recovered from source. Covers the two techniques implemented in
# `Analyzer::Mobile::Ios`:
#   A) `url.host == SomeEnum.someCase.rawValue` -> resolve the enum's full
#      case list, cross only with the app's *primary* scheme family.
#   B) a hardcoded `"scheme://host/path"` string literal.
describe "Analyzer::Mobile::Ios (code-level route harvesting)" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios_code_routes"))

  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_ENTITLEMENTS)
  CodeLocator.instance.reset_files
  CodeLocator.instance.push(Noir::LocatorKeys::IOS_INFO_PLIST, File.join(base, "Info.plist"))
  swift_path = File.join(base, "Routing.swift")
  CodeLocator.instance.register_file(swift_path, File.read(swift_path))

  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "still emits the bare schemes from Info.plist" do
    find.call("myapp://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("myappauth://").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "harvests a host from an enum compared via .rawValue against .host" do
    find.call("myapp://settings").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "harvests every case of that enum, not just the one referenced in code" do
    # `profilePage = "profile"` is never compared against `.host` anywhere in
    # the fixture — only `settings` is — but the whole enum's case list is
    # the router's real vocabulary, so it should surface too.
    find.call("myapp://profile").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "does not cross the harvested host with a non-primary scheme" do
    # `myappauth` is a second, separate CFBundleURLTypes entry (an auth
    # callback scheme) — it never shared a routing surface with `myapp` in
    # the plist, so it must not be crossed with `myapp`'s harvested hosts.
    find.call("myappauth://settings").should be_nil
    find.call("myappauth://profile").should be_nil
  end

  it "harvests a hardcoded full deep-link URL literal" do
    find.call("myapp://legacy/debug").not_nil!.protocol.should eq("mobile-scheme")
  end
end

describe "Analyzer::Mobile::Ios (format-string literals)" do
  dir = File.tempname("noir-ios-format-literals")
  Dir.mkdir_p(dir)
  plist = File.join(dir, "Info.plist")
  swift = File.join(dir, "Links.swift")
  File.write(plist, <<-XML)
    <plist version="1.0"><dict>
    <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>demo</string></array></dict></array>
    </dict></plist>
    XML
  File.write(swift, <<-SWIFT)
    let media = String(format: "demo://media?action=play&id=%@&page=%lu", itemId, page)
    let price = String(format: "demo://price?amount=%.2f&count=%zu", amount, count)
    let search = "demo://search?q=hello%20world"
    let plain = "demo://items/list"
    SWIFT

  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_ENTITLEMENTS)
  CodeLocator.instance.reset_files
  CodeLocator.instance.push(Noir::LocatorKeys::IOS_INFO_PLIST, plist)
  CodeLocator.instance.register_file(swift, File.read(swift))
  urls = Analyzer::Mobile::Ios.new(create_test_options).analyze.map(&.url)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(dir)

  it "skips a Swift literal carrying printf format specifiers" do
    urls.any?(&.starts_with?("demo://media")).should be_false
    urls.any?(&.starts_with?("demo://price")).should be_false
  end

  it "keeps percent-escapes and plain literals" do
    urls.should contain("demo://search?q=hello%20world")
    urls.should contain("demo://items/list")
  end
end

# A host enum read only inside a dispatcher that runs under a secondary
# scheme's guard belongs to that scheme, not to the primary one.
describe "Analyzer::Mobile::Ios (secondary-scheme dispatchers)" do
  dir = File.tempname("noir-ios-secondary-scheme")
  Dir.mkdir_p(dir)
  plist = File.join(dir, "Info.plist")
  swift = File.join(dir, "Router.swift")
  constants = File.join(dir, "SchemeName.swift")
  File.write(plist, <<-XML)
    <plist version="1.0"><dict>
    <key>CFBundleURLTypes</key><array>
    <dict><key>CFBundleURLSchemes</key><array><string>demo</string></array></dict>
    <dict><key>CFBundleURLSchemes</key><array><string>demolink</string></array></dict>
    <dict><key>CFBundleURLSchemes</key><array><string>demoshare</string></array></dict>
    </array></dict></plist>
    XML
  File.write(constants, <<-SWIFT)
    public final class SchemeName {
        #if DEBUG
        public static let share = "demoshare-dev"
        #else
        public static let share = "demoshare"
        #endif
    }
    SWIFT
  File.write(swift, <<-SWIFT)
    import Foundation
    public enum LinkHost: String {
        case send
        case copy
    }
    public enum ShareHost: String {
        case post
    }
    public enum ItemHost: String {
        case item
    }
    enum SchemeKind: Int {
        case share
        var urlScheme: String? {
            switch self {
            case .share:
                return SchemeName.share
            }
        }
    }
    final class Router {
        func handle(_ url: URL) -> Bool {
            let urlScheme = url.scheme
            if url.scheme == "demolink" {
                return handleLink(url)
            } else if SchemeKind.share.urlScheme == urlScheme {
                return handleShare(url)
            }
            return handleItem(url)
        }
        private func handleLink(_ url: URL) -> Bool {
            if LinkHost.send.rawValue == url.host {
                return true
            }
            if ItemHost.item.rawValue == url.host {
                return true
            }
            return false
        }
        func sendURL() -> URL? {
            var components = URLComponents()
            components.scheme = "demolink"
            components.host = LinkHost.send.rawValue
            return components.url
        }
        private func handleShare(_ url: URL) -> Bool {
            return ShareHost.post.rawValue == url.host
        }
        private func handleItem(_ url: URL) -> Bool {
            return url.host == ItemHost.item.rawValue
        }
    }
    SWIFT

  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_ENTITLEMENTS)
  CodeLocator.instance.reset_files
  CodeLocator.instance.push(Noir::LocatorKeys::IOS_INFO_PLIST, plist)
  [swift, constants].each { |path| CodeLocator.instance.register_file(path, File.read(path)) }
  urls = Analyzer::Mobile::Ios.new(create_test_options).analyze.map(&.url)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(dir)

  # `sendURL` only builds a link (an assignment, not a routing decision),
  # so it does not pull LinkHost back onto the primary scheme.
  it "credits hosts to the scheme a literal guard selects" do
    urls.should contain("demolink://send")
    urls.should contain("demolink://copy")
    urls.should_not contain("demo://send")
    urls.should_not contain("demo://copy")
  end

  it "resolves a guard through an enum property and a static constant" do
    urls.should contain("demoshare://post")
    urls.should_not contain("demo://post")
    urls.should_not contain("demoshare-dev://post")
  end

  it "keeps the primary scheme when the enum is also read by an unguarded router" do
    urls.should contain("demo://item")
    urls.should contain("demolink://item")
  end
end

# Runs the analyzer over a `demo` + `demolink` plist and the given Swift
# files (registered in order) and returns the emitted URLs.
private def secondary_scheme_urls(sources : Array(Tuple(String, String))) : Array(String)
  dir = File.tempname("noir-ios-secondary-negative")
  Dir.mkdir_p(dir)
  plist = File.join(dir, "Info.plist")
  File.write(plist, <<-XML)
    <plist version="1.0"><dict>
    <key>CFBundleURLTypes</key><array>
    <dict><key>CFBundleURLSchemes</key><array><string>demo</string></array></dict>
    <dict><key>CFBundleURLSchemes</key><array><string>demolink</string></array></dict>
    </array></dict></plist>
    XML
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_ENTITLEMENTS)
  CodeLocator.instance.reset_files
  CodeLocator.instance.push(Noir::LocatorKeys::IOS_INFO_PLIST, plist)
  sources.each do |name, body|
    path = File.join(dir, name)
    File.write(path, body)
    CodeLocator.instance.register_file(path, body)
  end
  Analyzer::Mobile::Ios.new(create_test_options).analyze.map(&.url)
ensure
  CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(dir) if dir
end

describe "Analyzer::Mobile::Ios (secondary-scheme dispatchers, unguarded routers)" do
  link_enum = "enum LinkHost: String {\n    case send\n}\n"

  it "keeps the primary scheme when another file calls the dispatcher unguarded" do
    urls = secondary_scheme_urls([
      {"Router.swift", link_enum + <<-SWIFT},
        final class Router {
            func route(_ url: URL) -> Bool {
                if url.scheme == "demolink" {
                    return handleLink(url)
                }
                return false
            }
            func handleLink(_ url: URL) -> Bool {
                return LinkHost.send.rawValue == url.host
            }
        }
        SWIFT
      {"AppDelegate.swift", <<-SWIFT},
        final class AppDelegate {
            let router = Router()
            func open(_ url: URL) -> Bool {
                return router.handleLink(url)
            }
        }
        SWIFT
    ])
    urls.should contain("demo://send")
  end

  it "keeps the primary scheme for a comparison after the guarded func ends" do
    urls = secondary_scheme_urls([
      {"Router.swift", link_enum + <<-SWIFT},
        final class Router {
            var url: URL?
            func route(_ url: URL) -> Bool {
                if url.scheme == "demolink" {
                    return handleLink(url)
                }
                return false
            }
            private func handleLink(_ url: URL) -> Bool {
                return LinkHost.send.rawValue == url.host
            }
            var isSend: Bool {
                return url?.host == LinkHost.send.rawValue
            }
        }
        SWIFT
    ])
    urls.should contain("demo://send")
  end

  it "keeps the primary scheme when the enum cap stops the scan early" do
    enums = (1..21).map { |i| "enum Host#{i}: String {\n    case h#{i}\n}\n" }.join
    checks = (1..21).map { |i| "        if Host#{i}.h#{i}.rawValue == url.host { return true }\n" }.join
    urls = secondary_scheme_urls([
      {"Dispatch.swift", link_enum + enums + <<-SWIFT},
        final class Dispatch {
            func route(_ url: URL) -> Bool {
                if url.scheme == "demolink" {
                    return handleLink(url)
                }
                return false
            }
            private func handleLink(_ url: URL) -> Bool {
                if LinkHost.send.rawValue == url.host { return true }
        #{checks}        return false
            }
        }
        SWIFT
      {"Other.swift", "func check(_ url: URL) -> Bool {\n    return url.host == LinkHost.send.rawValue\n}\n"},
    ])
    urls.should contain("demo://send")
    urls.should contain("demolink://send")
  end
end
