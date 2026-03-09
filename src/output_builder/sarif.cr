require "../models/output_builder"
require "../models/endpoint"
require "sarif"

class OutputBuilderSarif < OutputBuilder
  def print(endpoints : Array(Endpoint))
    message = build_sarif(endpoints, [] of PassiveScanResult)
    ob_puts message
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    message = build_sarif(endpoints, passive_results)
    ob_puts message
  end

  private def build_sarif(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    log = Sarif::Builder.build do |b|
      b.run("OWASP Noir", Noir::VERSION) do |r|
        r.information_uri("https://github.com/owasp-noir/noir")

        # Add endpoint discovery rule
        if endpoints.size > 0
          r.rule("endpoint-discovery",
            name: "Endpoint Discovery",
            short_description: "Discovered API endpoints through static analysis",
            full_description: "This rule identifies API endpoints, their HTTP methods, and parameters discovered through static code analysis",
            level: Sarif::Level::Note,
            help_uri: "https://github.com/owasp-noir/noir")
        end

        # Add passive scan rules
        passive_results.group_by(&.id).each_value do |results_for_rule|
          result = results_for_rule.first
          help_uri = result.info.reference.empty? ? nil : result.info.reference[0].to_s
          r.rule(result.id,
            name: result.info.name,
            short_description: result.info.name,
            full_description: result.info.description,
            level: map_severity_to_sarif_level(result.info.severity),
            help_uri: help_uri)
        end

        # Add endpoint results
        endpoints.each do |endpoint|
          bake_endpoint(endpoint.url, endpoint.params)
          params_info = [] of String

          endpoint.params.each do |param|
            params_info << "#{param.param_type}: #{param.name}"
          end

          message_text = "#{endpoint.method} #{endpoint.url}"
          if params_info.size > 0
            message_text += " (Parameters: #{params_info.join(", ")})"
          end

          if endpoint.details.code_paths && endpoint.details.code_paths.size > 0
            r.result do |rb|
              rb.message(message_text)
              rb.rule_id("endpoint-discovery")
              rb.level(Sarif::Level::Note)
              endpoint.details.code_paths.each do |code_path|
                rb.location(uri: code_path.path, start_line: code_path.line)
              end
            end
          else
            r.result(message_text,
              rule_id: "endpoint-discovery",
              level: Sarif::Level::Note)
          end
        end

        # Add passive scan results
        passive_results.each do |result|
          r.result(result.extract,
            rule_id: result.id,
            level: map_severity_to_sarif_level(result.info.severity),
            uri: result.file_path,
            start_line: result.line_number)
        end
      end
    end

    log.to_json
  end

  private def map_severity_to_sarif_level(severity : String) : Sarif::Level
    case severity.downcase
    when "critical", "high"
      Sarif::Level::Error
    when "medium"
      Sarif::Level::Warning
    when "low"
      Sarif::Level::Note
    else
      Sarif::Level::None
    end
  end
end
