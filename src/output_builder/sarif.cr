require "../models/output_builder"
require "../models/endpoint"
require "json"

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
    sarif = JSON.build do |json|
      json.object do
        json.field "$schema", "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"
        json.field "version", "2.1.0"
        json.field "runs" do
          json.array do
            json.object do
              json.field "tool" do
                json.object do
                  json.field "driver" do
                    json.object do
                      json.field "name", "OWASP Noir"
                      json.field "version", "0.25.0"
                      json.field "informationUri", "https://github.com/owasp-noir/noir"
                      json.field "rules" do
                        build_rules(json, endpoints, passive_results)
                      end
                    end
                  end
                end
              end
              json.field "results" do
                build_results(json, endpoints, passive_results)
              end
            end
          end
        end
      end
    end

    sarif
  end

  private def build_rules(json : JSON::Builder, endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    json.array do
      # Add endpoint discovery rule
      if endpoints.size > 0
        json.object do
          json.field "id", "endpoint-discovery"
          json.field "name", "Endpoint Discovery"
          json.field "shortDescription" do
            json.object do
              json.field "text", "Discovered API endpoints through static analysis"
            end
          end
          json.field "fullDescription" do
            json.object do
              json.field "text", "This rule identifies API endpoints, their HTTP methods, and parameters discovered through static code analysis"
            end
          end
          json.field "defaultConfiguration" do
            json.object do
              json.field "level", "note"
            end
          end
          json.field "helpUri", "https://github.com/owasp-noir/noir"
        end
      end

      # Add passive scan rules
      added_rule_ids = Set(String).new
      passive_results.each do |result|
        rule_id = result.id
        unless added_rule_ids.includes?(rule_id)
          added_rule_ids.add(rule_id)
          json.object do
            json.field "id", rule_id
            json.field "name", result.info.name
            json.field "shortDescription" do
              json.object do
                json.field "text", result.info.name
              end
            end
            json.field "fullDescription" do
              json.object do
                json.field "text", result.info.description
              end
            end
            json.field "defaultConfiguration" do
              json.object do
                json.field "level", map_severity_to_sarif_level(result.info.severity)
              end
            end
            unless result.info.reference.empty?
              json.field "helpUri", result.info.reference[0].to_s
            end
          end
        end
      end
    end
  end

  private def build_results(json : JSON::Builder, endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    json.array do
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

        json.object do
          json.field "ruleId", "endpoint-discovery"
          json.field "level", "note"
          json.field "message" do
            json.object do
              json.field "text", message_text
            end
          end

          # Add location information if available
          if endpoint.details.code_paths && endpoint.details.code_paths.size > 0
            json.field "locations" do
              json.array do
                endpoint.details.code_paths.each do |code_path|
                  json.object do
                    json.field "physicalLocation" do
                      json.object do
                        json.field "artifactLocation" do
                          json.object do
                            json.field "uri", code_path.path
                          end
                        end
                        if code_path.line
                          json.field "region" do
                            json.object do
                              json.field "startLine", code_path.line
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Add passive scan results
      passive_results.each do |result|
        json.object do
          json.field "ruleId", result.id
          json.field "level", map_severity_to_sarif_level(result.info.severity)
          json.field "message" do
            json.object do
              json.field "text", result.extract
            end
          end
          json.field "locations" do
            json.array do
              json.object do
                json.field "physicalLocation" do
                  json.object do
                    json.field "artifactLocation" do
                      json.object do
                        json.field "uri", result.file_path
                      end
                    end
                    json.field "region" do
                      json.object do
                        json.field "startLine", result.line_number
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  private def map_severity_to_sarif_level(severity : String) : String
    case severity.downcase
    when "critical", "high"
      "error"
    when "medium"
      "warning"
    when "low"
      "note"
    else
      "none"
    end
  end
end
