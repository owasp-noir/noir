require "../../../models/analyzer"
require "../../../miniparsers/wcf_extractor"
require "./common"

module Analyzer::CSharp
  # Code-first WCF REST (`[WebGet]` / `[WebInvoke]` UriTemplates), the HTTP
  # surface of services that ship no WSDL. Routes are relative to the service
  # base address, which lives in hosting config (`.svc`, `ServiceRoute`,
  # `WebServiceHost`) rather than on the contract.
  class Wcf < Analyzer
    analyzer_for "cs_wcf"

    PLACEHOLDER = /\{([^{}]+)\}/

    def analyze
      get_files_by_extension(".cs").each do |file|
        next if Common.csharp_test_path?(base_relative_path(file))

        Noir::WcfExtractor.extract(read_file_content(file)).each do |operation|
          # `Method = "*"` answers every verb.
          verbs = operation.verb == "*" ? WILDCARD_HTTP_METHODS : [operation.verb]
          verbs.each { |verb| @result << endpoint(file, operation, verb) }
        end
      end

      @result
    end

    private def endpoint(file : String, operation : Noir::WcfExtractor::Operation, verb : String) : Endpoint
      path, _, query = (operation.uri_template || operation.name).partition('?')
      # `{id=5}` / `{*rest}` read as the bare variable, as ASP.NET's do.
      path = path.gsub(PLACEHOLDER) { "{#{Common.route_placeholder_name($1)}}" }
      endpoint = Endpoint.new("/#{path.lchop('/')}", verb, Details.new(PathInfo.new(file, operation.line)))
      bound = Set(String).new

      path.scan(PLACEHOLDER) do |m|
        endpoint.push_param(Param.new(m[1], "", "path"))
        bound << m[1].downcase
      end
      query.split('&') do |pair|
        key, _, value = pair.partition('=')
        next if key.empty?
        endpoint.push_param(Param.new(key, "", "query"))
        value.scan(PLACEHOLDER) { |m| bound << Common.route_placeholder_name(m[1]).downcase }
      end

      # Parameters the template does not bind come from the query string on
      # GET (the only place an undeclared template puts them) and from the
      # request body otherwise.
      operation.params.each do |name|
        next if bound.includes?(name.downcase)
        endpoint.push_param(Param.new(name, "", verb == "GET" ? "query" : "json"))
      end

      endpoint
    end
  end
end
