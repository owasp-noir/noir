require "../../../models/analyzer"
require "../../../miniparsers/apex_extractor"
require "../../../detector/detectors/apex/salesforce"

module Analyzer::Apex
  # Salesforce Apex entry points declared in `.cls` files:
  #
  # - `@RestResource(urlMapping='/x/*')` + `@HttpGet`/`@HttpPost`/... methods
  #   are served at `/services/apexrest/x/*`. Method arguments are the JSON
  #   body fields; `RestContext.request.params.get('k')` reads are query
  #   params and `.headers.get('k')` reads are headers.
  # - `@AuraEnabled static` methods are Aura/LWC actions, all POSTed to one
  #   `/aura` endpoint (`/s/sfsites/aura` on Experience Cloud sites) and
  #   dispatched on the action descriptor in the form-encoded `message`.
  #   Noir keys endpoints on (method, url), so the descriptor rides in the
  #   URL fragment, the same convention as OpenRPC's `/rpc#method`:
  #   `POST /aura#apex://CaseController/ACTION$getCases`.
  # - `webservice static` methods are SOAP operations on
  #   `/services/Soap/class/<Class>`, disambiguated by `#<method>`.
  #
  # ponytail: a managed package's namespace prefix (`/services/apexrest/ns/...`,
  # `apex://ns.Class/...`) is not read from sfdx-project.json.
  class Salesforce < Analyzer
    analyzer_for "apex_salesforce"

    TAGGER     = "apex_analyzer"
    REST_VERBS = {"httpget" => "GET", "httppost" => "POST", "httpput" => "PUT", "httppatch" => "PATCH", "httpdelete" => "DELETE"}
    BODYLESS   = Set{"GET", "DELETE"}

    URL_MAPPING_RE     = /\burlMapping\s*=\s*'([^']*)'/i
    QUERY_READ_RE      = /\.params\s*\.\s*get\s*\(\s*'([^']+)'\s*\)/i
    HEADER_READ_RE     = /\.headers\s*\.\s*get\s*\(\s*'([^']+)'\s*\)/i
    STATIC_RE          = /\bstatic\b/i
    WEBSERVICE_RE      = /\bwebservice\b/i
    WITHOUT_SHARING_RE = /\bwithout\s+sharing\b/i

    def analyze
      ordered_scan_files(get_files_by_extension(".cls")) { |path| analyze_file(path) }.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def analyze_file(path : String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.matches?(Detector::Apex::Salesforce::ENTRY_RE)
      klass = Noir::ApexExtractor.parse(source) || return
      return if klass.annotations.includes?("istest")

      rest_base = nil
      if klass.annotations.includes?("restresource") && (mapping = klass.header.match(URL_MAPPING_RE))
        rest_base = "/services/apexrest/#{mapping[1].lchop('/')}"
      end
      without_sharing = klass.header.matches?(WITHOUT_SHARING_RE)

      endpoints = [] of Endpoint
      klass.members.each do |member|
        next unless member.header.matches?(STATIC_RE)
        details = Details.new(PathInfo.new(path, member.line))

        if rest_base && (verb = member.annotations.compact_map { |a| REST_VERBS[a]? }.first?)
          params = BODYLESS.includes?(verb) ? [] of Param : member.args.map { |arg| Param.new(arg, "", "json") }
          member.body.scan(QUERY_READ_RE) { |m| params << Param.new(m[1], "", "query") }
          member.body.scan(HEADER_READ_RE) { |m| params << Param.new(m[1], "", "header") }
          endpoints << Endpoint.new(rest_base, verb, unique_params(params), details)
        end

        if member.annotations.includes?("auraenabled")
          params = member.args.map { |arg| Param.new(arg, "", "json") }
          endpoints << Endpoint.new("/aura#apex://#{klass.name}/ACTION$#{member.name}", "POST", params, details)
        end

        if member.header.matches?(WEBSERVICE_RE)
          params = [Param.new("SOAPAction", "", "header"), Param.new("Content-Type", "text/xml; charset=utf-8", "header")]
          params.concat(member.args.map { |arg| Param.new(arg, "", "json") })
          endpoints << Endpoint.new("/services/Soap/class/#{klass.name}##{member.name}", "POST", params, details)
        end
      end

      if without_sharing
        tag = Tag.new("apex-without-sharing", "Apex class runs without sharing: record-level access is not enforced", TAGGER)
        endpoints.map! { |endpoint| endpoint.add_tag(tag); endpoint }
      end
      endpoints
    end
  end
end
