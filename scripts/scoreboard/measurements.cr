require "json"
require "../../src/utils/url_path"

module Scoreboard
  OAS_TECHS = %w[oas2 oas3]
  GUARDS    = %w[both_guarded both_open spec_guarded_code_open spec_open_code_guarded]

  private def http_rows(report)
    report["endpoints"].as_a.select { |row| row["protocol"]?.try(&.as_s) == "http" }
  end

  # The inputs have already passed through the optimizer. Only the displayed
  # spelling of a placeholder can differ between a merged row and its source.
  private def address(row)
    url = row["url"].as_s
    {row["method"].as_s, row["kind"]? == "regex" ? url : Noir::URLPath.unify_path_placeholders(url)}
  end

  private def code_rows(report, technology)
    http_rows(report).select { |row| contributors(row).includes?(technology) }
  end

  # Keep the scored contributor's scope even if another analyzer won the merge.
  private def detection_index(report, technology)
    code_rows(report, technology).group_by do |row|
      origins = row["details"]["origins"]?.try(&.as_a) || [] of JSON::Any
      scopes = origins.compact_map do |origin|
        next unless origin["technology"] == technology
        %w[project platform application variant].map { |key| origin[key]?.try(&.as_s?) || "" }
      end.uniq!.sort!
      {address(row), scopes}
    end
  end

  def detection_rows(forced, automatic, technology)
    left = detection_index(forced, technology)
    right = detection_index(automatic, technology)
    forced_only = [] of JSON::Any
    automatic_only = [] of JSON::Any
    (left.keys | right.keys).each do |key|
      forced_rows = left.fetch(key) { [] of JSON::Any }
      auto_rows = right.fetch(key) { [] of JSON::Any }.dup
      # Cancel identical spellings first, then equivalent placeholder slots.
      remaining = forced_rows.reject do |row|
        if i = auto_rows.index { |other| other["url"] == row["url"] }
          auto_rows.delete_at(i)
          true
        end
      end
      paired = Math.min(remaining.size, auto_rows.size)
      forced_only.concat(remaining.skip(paired))
      automatic_only.concat(auto_rows.skip(paired))
    end
    {forced_only: delta_rows(forced_only), automatic_only: delta_rows(automatic_only)}
  end

  private def delta_rows(endpoints)
    endpoints.map do |row|
      JSON.parse({method: row["method"], url: row["url"], locations: row["details"]["code_paths"]?}.to_json)
    end.sort_by! { |row| {row["method"].as_s, row["url"].as_s, row["locations"].to_json} }
  end

  def detection(automatic, pins, technology, delta)
    detected = automatic["scan_technologies"].as_a.map(&.as_s).uniq!.sort!
    JSON.parse({detected: detected.includes?(technology), other_technologies: detected - pins,
                forced_only: delta[:forced_only].size, automatic_only: delta[:automatic_only].size}.to_json)
  end

  # The optimizer may retain same-shaped siblings (e.g. Spring request
  # conditions). Use the locations the forced merge kept to recover its row.
  private def side_row(index, merged, side)
    candidates = index.fetch(address(merged)) { [] of JSON::Any }
    return candidates.first if candidates.size == 1
    if paths = merged["details"]["code_paths"]?.try(&.as_a)
      located = candidates.select { |row| row["details"]["code_paths"]?.try(&.as_a.any? { |path| paths.includes?(path) }) }
      candidates = located unless located.empty?
    end
    return candidates.first if candidates.size == 1
    exact = candidates.select { |row| row["url"] == merged["url"] }
    return exact.first if exact.size == 1
    raise "Cannot identify #{side} row for #{merged["method"]} #{merged["url"]} (#{candidates.size} candidates)"
  end

  private def parameter_sets(row)
    params = Set({String, String}).new
    body = Set(String).new
    inputs = row["params"].as_a
    path_names = inputs.compact_map { |param| param["name"].as_s if param["param_type"] == "path" }
    slots = Noir::URLPath.placeholder_names(row["url"].as_s, path_names)
    inputs.each do |param|
      location = param["param_type"].as_s
      name = param["name"].as_s
      case location
      when "path"
        positions = slots.each_index.select { |i| slots[i] == name }.to_a
        if positions.empty?
          params << {location, name}
        else
          positions.each { |position| params << {"path-slot", position.to_s} }
        end
      when "header"
        params << {location, name.downcase}
      when "query", "cookie"
        params << {location, name}
      when "json", "body"
        body << name unless name == "body"
      when "form"
        body << name
      end
    end
    {params, body}
  end

  private class Overlap
    @both = 0
    @spec_only = 0
    @code_only = 0

    def add(spec, code)
      both = (spec & code).size
      @both += both
      @spec_only += spec.size - both
      @code_only += code.size - both
    end

    def report
      Scoreboard.overlap_report(@both, @spec_only, @code_only)
    end
  end

  def overlap_report(both, spec_only, code_only)
    {both: both, spec_only: spec_only, code_only: code_only,
     recall: ratio(both, both + spec_only), agreement: ratio(both, both + code_only)}
  end

  private def guard_bucket(document, code)
    declared = document["tags"].as_a.any? { |tag| tag["name"] == "auth" && tag["tagger"].as_s.in?("oas2_access", "oas3_access") }
    guarded = code["tags"].as_a.any? { |tag| tag["name"] == "auth" && tag["tagger"].as_s.ends_with?("_auth") }
    if declared
      guarded ? "both_guarded" : "spec_guarded_code_open"
    else
      guarded ? "spec_open_code_guarded" : "both_open"
    end
  end

  def matched_measurements(forced, code_report, spec_report, technology)
    code_index = code_rows(code_report, technology).group_by { |row| address(row) }
    spec_index = http_rows(spec_report).select { |row| contributors(row).any? { |tech| OAS_TECHS.includes?(tech) } }.group_by { |row| address(row) }
    params = Overlap.new
    bodies = Overlap.new
    guards = GUARDS.to_h { |key| {key, 0} }
    code_rows(forced, technology).each do |merged|
      next unless contributors(merged).any? { |tech| OAS_TECHS.includes?(tech) }
      code = side_row(code_index, merged, technology)
      document = side_row(spec_index, merged, "OpenAPI")
      spec_params, spec_body = parameter_sets(document)
      code_params, code_body = parameter_sets(code)
      params.add(spec_params, code_params)
      bodies.add(spec_body, code_body)
      guards[guard_bucket(document, code)] += 1
    end
    JSON.parse({params: params.report, body_fields: bodies.report, guards: guards}.to_json)
  end

  def measurement_totals(repositories)
    detection = repositories.map(&.["detection"])
    totals = JSON.parse({
      detection: {
        detected_repositories: detection.count(&.["detected"].as_bool),
        other_technologies:    detection.flat_map(&.["other_technologies"].as_a.map(&.as_s)).uniq!.sort!,
        forced_only:           detection.sum(&.["forced_only"].as_i),
        automatic_only:        detection.sum(&.["automatic_only"].as_i),
      },
      guards: GUARDS.to_h { |key| {key, repositories.sum(&.["guards"][key].as_i)} },
    }.to_json)
    %w[params body_fields].each do |field|
      counts = repositories.map(&.[field])
      totals.as_h[field] = JSON.parse(overlap_report(counts.sum(&.["both"].as_i), counts.sum(&.["spec_only"].as_i), counts.sum(&.["code_only"].as_i)).to_json)
    end
    totals
  end
end
