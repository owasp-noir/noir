require "../models/endpoint"
require "../models/code_locator"
require "../ext/tree_sitter/tree_sitter"
require "../miniparsers/kotlin_callee_extractor"
require "../miniparsers/java_callee_extractor"
require "../miniparsers/swift_callee_extractor"
require "../miniparsers/objc_callee_extractor"
require "../utils/text_file"
require "../utils/path_scope"
require "./linker/android"
require "./linker/ios"

# Post-analysis pass that links mobile deep-link endpoints (produced by the
# config-file analyzers from AndroidManifest.xml) to the source code that
# handles them. For each Android mobile endpoint it:
#
#   1. resolves the handling component (metadata["via"] / the intent://
#      component) to its .kt/.java source file,
#   2. adds that file as a `code_path` so the AI-context builder scans the
#      handler body for sinks/guards, and
#   3. extracts the handler's 1-hop callees into `endpoint.callees`.
#
# The existing AIContext builder then derives sinks/guards/sources from the
# handler snippet and callees — no mobile-specific wiring needed there. iOS
# endpoints have no per-endpoint `via`, so the linker discovers central
# App/SceneDelegate/SwiftUI handlers and attaches them by deep-link kind.
module NoirMobileLinker
  def self.apply(endpoints : Array(Endpoint), logger : NoirLogger) : Array(Endpoint)
    link_android(endpoints, logger)
    link_ios(endpoints, logger)
    endpoints
  end

  private def self.apply_handler_info(endpoint : Endpoint, info : HandlerInfo) : Endpoint
    info.code_paths.each { |pi| endpoint.details.add_path(pi) }
    info.callees.each { |callee| endpoint.push_callee(callee) }
    info.params.each { |param| endpoint.push_param(param) }
    endpoint
  end

  # Content cache may be cold (budget exhausted, or caching disabled in
  # tests); fall back to a direct read per the CodeLocator contract.
  def self.read_content(path : String) : String?
    cached = CodeLocator.instance.content_for(path)
    return cached if cached
    return unless File.exists?(path)
    Noir::TextFile.read(path)
  end

  # Aggregated handler evidence to graft onto an endpoint.
  struct HandlerInfo
    getter code_paths : Array(PathInfo)
    getter callees : Array(Callee)
    getter params : Array(Param)

    def initialize
      @code_paths = [] of PathInfo
      @callees = [] of Callee
      @params = [] of Param
    end

    def empty? : Bool
      @code_paths.empty? && @callees.empty? && @params.empty?
    end
  end
end
