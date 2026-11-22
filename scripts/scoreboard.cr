require "json"
require "yaml"
require "file_utils"
require "uri"
require "../src/techs/techs"
require "./scoreboard/measurements"

# Run only through `just scoreboard`. Requiring this module in the unit suite
# exercises arithmetic without checking out repositories or running scanners.
module Scoreboard
  extend self

  RESULTS    = "scripts/scoreboard/results.json"
  ROWS       = "tmp/scoreboard"
  PIN_FIELDS = %w[name url commit technologies scope specs spec_prefix exclude_paths]

  def contributors(endpoint : JSON::Any) : Array(String)
    details = endpoint["details"]
    technologies = details["technologies"]?.try(&.as_a.map(&.as_s)) || [] of String
    technologies.empty? ? [details["technology"]?.try(&.as_s)].compact : technologies
  end

  def score(report : JSON::Any, technology : String) : JSON::Any
    matched = spec_only = code_only = marked = 0
    claims = Hash(String, Int32).new(0)
    report["endpoints"].as_a.each do |endpoint|
      next unless endpoint["protocol"]?.try(&.as_s) == "http"
      technologies = contributors(endpoint)
      code = technologies.includes?(technology)
      spec = technologies.any? { |tech| NoirTechs.view(tech) == "spec" }
      if code && spec
        matched += 1
      elsif code
        code_only += 1
      elsif spec
        spec_only += 1
      end
      if code && (marks = endpoint["resolution"]?.try(&.as_h)) && !marks.empty?
        marked += 1
        marks.each { |claim, status| claims["#{claim}:#{status.as_s}"] += 1 }
      end
    end
    code_count = matched + code_only
    JSON.parse({matched: matched, spec_only: spec_only, code_only: code_only,
                recall: ratio(matched, matched + spec_only), agreement: ratio(matched, code_count),
                marked: marked, marked_share: ratio(marked, code_count),
                claims: claims.keys.sort!.to_h { |key| {key, {count: claims[key], share: ratio(claims[key], code_count)}} }}.to_json)
  end

  def ratio(numerator : Int32, denominator : Int32) : Float64?
    numerator.to_f / denominator unless denominator == 0
  end

  def command(program : String, args : Array(String), output : Process::Stdio = Process::Redirect::Close)
    status = Process.run(program, args, output: output, error: :inherit)
    raise "#{program} #{args.first?} failed (#{status.exit_code})" unless status.success?
  end

  # Same pinned, shallow fetch as agent_bench.cr; no repository code is run.
  def checkout(repo : JSON::Any, work : String) : String
    dir = File.join(work, repo["name"].as_s)
    commit = repo["commit"].as_s
    raise "Expected a full commit SHA" unless commit.matches?(/\A[0-9a-f]{40}\z/)
    # The work directory lives under TMPDIR, where periodic cleanup removes
    # old files and leaves the directories: a checkout without its HEAD is
    # not a repository any more, so start it over.
    FileUtils.rm_rf(dir) if Dir.exists?(dir) && !File.exists?(File.join(dir, ".git", "HEAD"))
    unless Dir.exists?(dir)
      Dir.mkdir_p(dir)
      command("git", ["-C", dir, "init", "-q"])
      command("git", ["-C", dir, "remote", "add", "origin", repo["url"].as_s])
    end
    head = IO::Memory.new
    Process.run("git", ["-C", dir, "rev-parse", "HEAD"], output: head, error: :close)
    if head.to_s.strip != commit
      command("git", ["-C", dir, "fetch", "-q", "--depth", "1", "origin", commit])
      command("git", ["-C", dir, "checkout", "-q", "--detach", "FETCH_HEAD"])
    end
    dir
  end

  # Change only declared server metadata before Noir performs its own join.
  def strip_spec_prefix!(doc : JSON::Any, prefix : String)
    raise "spec_prefix must be a non-root path without a trailing slash" if !prefix.starts_with?('/') || prefix.size <= 1 || prefix.ends_with?('/')
    if doc["swagger"]?.try(&.as_s) == "2.0"
      raise "spec_prefix #{prefix} differs from declared basePath" unless doc["basePath"]?.try(&.as_s) == prefix
      doc.as_h["basePath"] = JSON::Any.new("/")
      return
    end
    raise "spec_prefix requires OpenAPI 3 servers" unless doc["openapi"]?.try(&.as_s.starts_with?("3."))
    servers = doc["servers"].as_a
    raise "spec_prefix requires declared servers" if servers.empty?
    doc["paths"].as_h.each_value do |item|
      next unless fields = item.as_h?
      raise "Scoped servers need a separate prefix review" if fields.has_key?("servers") || fields.values.any? { |value| value.as_h?.try(&.has_key?("servers")) }
    end
    servers.each do |server|
      url = server["url"].as_s
      raise "spec_prefix #{prefix} differs from declared server #{url}" unless URI.parse(url).path == prefix && url.ends_with?(prefix)
      local = url[0...-prefix.size]
      server.as_h["url"] = JSON::Any.new(local.empty? ? "/" : local)
    end
  end

  def stage_repository(repo : JSON::Any, work : String) : String
    dir = checkout(repo, work)
    stage = File.join(work, "scan", repo["name"].as_s)
    FileUtils.rm_rf(stage)
    Dir.mkdir_p(stage)
    archive = File.join(work, "source.tar")
    specs = repo["specs"].as_a.map(&.as_s).sort!
    # Archive the pinned object, not potentially modified working files.
    command("git", ["-C", dir, "archive", "--format=tar", "-o", archive, repo["commit"].as_s, "--", repo["scope"].as_s] + specs)
    command("tar", ["-xf", archive, "-C", stage])
    File.delete(archive)
    specs.each { |path| raise "Missing spec #{path}" unless File.file?(File.join(stage, path)) }
    # Keep source/config intact, but exclude other OpenAPI entry documents.
    # Referenced fragments remain available to Noir's own $ref resolver.
    Dir.glob(File.join(stage, "**", "*.{json,yaml,yml}")).sort.each do |path|
      relative = path.delete_at(0, stage.size + 1)
      next if specs.includes?(relative)
      content = File.read(path)
      next unless content.matches?(/["']?(?:swagger|openapi)["']?\s*:/)
      doc = (YAML.parse(content) rescue nil).try(&.as_h?)
      if doc && (doc.has_key?(YAML::Any.new("openapi")) || doc.has_key?(YAML::Any.new("swagger")))
        File.delete(path)
      end
    end
    if prefix = repo["spec_prefix"]?.try(&.as_s)
      specs.each do |relative|
        path = File.join(stage, relative)
        doc = JSON.parse(YAML.parse(File.read(path)).to_json)
        strip_spec_prefix!(doc, prefix)
        File.write(path, path.ends_with?(".json") ? doc.to_pretty_json : YAML.parse(doc.to_json).to_yaml)
      end
    end
    stage
  end

  # `complete: false` is for the automatic scan. With every detector on, a
  # file one of them cannot read (a binary blob behind a `.ts` name) is
  # reported as skipped; that is a fact about the tree, counted in the
  # detection result, not a failed measurement.
  def scan(stage, base_args, scan_args, report_path, *, complete : Bool = true) : JSON::Any
    command("./bin/noir", ["scan", stage] + base_args + scan_args + ["-o", report_path], output: :close)
    report = JSON.parse(File.read(report_path))
    if complete && !report["errors"].as_a.empty?
      raise "Scanner reported incomplete coverage: #{report["errors"].to_json}"
    end
    report["endpoints"].as_a.each do |endpoint|
      endpoint["details"]["code_paths"].as_a.each do |location|
        location.as_h["path"] = JSON::Any.new(location["path"].as_s.sub(stage + "/", ""))
      end
    end
    report
  end

  def rows(report : JSON::Any, technology : String) : Array(JSON::Any)
    report["endpoints"].as_a.compact_map do |endpoint|
      next unless endpoint["protocol"]?.try(&.as_s) == "http"
      technologies = contributors(endpoint)
      code = technologies.includes?(technology)
      spec = technologies.any? { |tech| NoirTechs.view(tech) == "spec" }
      next unless code || spec
      side = code && spec ? "matched" : code ? "code-only" : "spec-only"
      JSON.parse({side: side, method: endpoint["method"], url: endpoint["url"], locations: endpoint["details"]["code_paths"]}.to_json)
    end.sort_by! { |row| {row["side"].as_s, row["method"].as_s, row["url"].as_s} }
  end

  # Round-robin over repository/side buckets; quantiles within each bucket
  # avoid auditing only alphabetically early URLs. Maximum 25 per technology.
  def sample(rows : Array(JSON::Any)) : Array(JSON::Any)
    buckets = rows.group_by { |row| {row["repository"].as_s, row["side"].as_s} }.to_a.sort_by(&.[0])
    quotas = Array(Int32).new(buckets.size, 0)
    Math.min(25, rows.size).times do
      index = quotas.each_index.select { |i| quotas[i] < buckets[i][1].size }.min_by { |i| {quotas[i], i} }
      quotas[index] += 1
    end
    buckets.map_with_index do |(_, bucket), index|
      quota = quotas[index]
      Array.new(quota) { |round| bucket[(round * bucket.size) // quota] }
    end.flatten
  end

  def percent(value : JSON::Any) : String
    value.raw.nil? ? "n/a" : "#{(value.as_f * 100).round(1)}%"
  end

  def table(rows : Array(JSON::Any), label : String, repository_counts : Bool = false) : String
    lines = ["| #{label} |#{repository_counts ? " Repositories |" : ""} Matched | Spec-only | Code-only | Recall | Agreement | Marked |", "| --- |#{repository_counts ? " ---: |" : ""} ---: | ---: | ---: | ---: | ---: | ---: |"]
    rows.each do |row|
      count = repository_counts ? " #{row["repositories"]} |" : ""
      lines << "| #{row["name"].as_s} |#{count} #{row["matched"]} | #{row["spec_only"]} | #{row["code_only"]} | #{percent(row["recall"])} | #{percent(row["agreement"])} | #{row["marked"]} (#{percent(row["marked_share"])}) |"
    end
    lines.join('\n')
  end

  def measurement_tables(totals, repositories) : String
    String.build do |io|
      io << "\n| Technology | Detected / repositories | Other technologies detected | Forced-only rows | Automatic-only rows |\n| --- | ---: | --- | ---: | ---: |\n"
      totals.each do |row|
        d = row["detection"]
        io << "| #{row["name"]} | #{d["detected_repositories"]} / #{row["repositories"]} | #{d["other_technologies"].as_a.join(", ")} | #{d["forced_only"]} | #{d["automatic_only"]} |\n"
      end
      io << "\n| Repository | Technology | Detected | Other technologies detected | Forced-only rows | Automatic-only rows |\n| --- | --- | --- | --- | ---: | ---: |\n"
      repositories.each do |row|
        d = row["detection"]
        io << "| #{row["name"]} | #{row["technology"]} | #{d["detected"]} | #{d["other_technologies"].as_a.join(", ")} | #{d["forced_only"]} | #{d["automatic_only"]} |\n"
      end
      io << "\n| Technology | Inputs on matched rows | Both | Document only | Code only | Recall | Agreement |\n| --- | --- | ---: | ---: | ---: | ---: | ---: |\n"
      totals.each do |row|
        {"params" => "Parameters", "body_fields" => "Body fields"}.each do |field, label|
          p = row[field]
          io << "| #{row["name"]} | #{label} | #{p["both"]} | #{p["spec_only"]} | #{p["code_only"]} | #{percent(p["recall"])} | #{percent(p["agreement"])} |\n"
        end
      end
      io << "\n| Technology | Both guarded | Both open | Document guarded, code open | Document open, code guarded |\n| --- | ---: | ---: | ---: | ---: |\n"
      totals.each do |row|
        io << "| #{row["name"]} | #{GUARDS.map { |key| row["guards"][key] }.join(" | ")} |\n"
      end
    end
  end

  def pin(repo : JSON::Any) : Hash(String, JSON::Any)
    repo.as_h.select { |key, _| PIN_FIELDS.includes?(key) }
  end

  def run
    started = Time.instant
    source_state = IO::Memory.new
    command("git", ["status", "--porcelain", "--untracked-files=all", "--", "src", "shard.yml", "shard.lock"], output: source_state)
    raise "Commit analyzer/dependency changes before publishing a scoreboard" unless source_state.to_s.empty?
    corpus = JSON.parse(File.read("scripts/scoreboard/corpus.json"))
    work = File.join(ENV.fetch("TMPDIR", "/tmp"), "noir-codex-scoreboard")
    Dir.mkdir_p(work)
    repos = corpus["repos"].as_a.sort_by(&.["name"].as_s)
    results = [] of JSON::Any
    reports = Hash(String, Array(JSON::Any)).new { |hash, tech| hash[tech] = [] of JSON::Any }
    unmatched = Hash(String, Array(JSON::Any)).new { |hash, tech| hash[tech] = [] of JSON::Any }
    Dir.mkdir_p(ROWS)
    config = File.join(work, "config.yml")
    File.write(config, "{}\n")
    repos.each do |repo|
      puts "Scoring #{repo["name"]} @ #{repo["commit"]}"
      stage = stage_repository(repo, work)
      pins = repo["technologies"].as_a.map(&.as_s).sort!
      exclusions = %w[*.wasm *.csv] + (repo["exclude_paths"]?.try(&.as_a.map(&.as_s)) || [] of String)
      base_args = ["--config-file", config, "--concurrency", "1", "--exclude-path", exclusions.join(','), "--no-log", "--no-color", "-f", "json"]
      path = File.join(work, repo["name"].as_s)
      report = scan(stage, base_args, ["--only-techs", (pins + OAS_TECHS).join(','), "--techs", pins.join(',')], "#{path}.json")
      automatic = scan(stage, base_args, [] of String, "#{path}-automatic.json", complete: false)
      document = scan(stage, base_args, ["--only-techs", OAS_TECHS.join(',')], "#{path}-oas.json")
      pins.each do |tech|
        code = scan(stage, base_args, ["--techs", tech, "--only-techs", tech, "--use-all-taggers"], "#{path}-#{tech}.json")
        delta = detection_rows(report, automatic, tech)
        reports[tech].concat(report["endpoints"].as_a)
        result = score(report, tech).as_h.merge(pin(repo))
        result.merge!(matched_measurements(report, code, document, tech).as_h)
        result["detection"] = detection(automatic, pins, tech, delta)
        result["technology"] = JSON::Any.new(tech)
        results << JSON::Any.new(result)
        File.write(File.join(ROWS, "#{repo["name"].as_s}-#{tech}-detection.json"), delta.to_pretty_json + "\n")
        partitions = rows(report, tech).group_by(&.["side"].as_s)
        %w[matched spec-only code-only].each { |side| partitions[side] ||= [] of JSON::Any }
        File.write(File.join(ROWS, "#{repo["name"].as_s}-#{tech}.json"), partitions.to_pretty_json + "\n")
        partitions.each do |side, entries|
          next if side == "matched"
          unmatched[tech].concat(entries.map { |row| JSON::Any.new(row.as_h.merge({"repository" => repo["name"]})) })
        end
      end
    end
    totals = reports.keys.sort!.map do |tech|
      result = score(JSON.parse({endpoints: reports[tech]}.to_json), tech).as_h
      result["name"] = JSON::Any.new(tech)
      repositories = results.select { |row| row["technology"] == tech }
      result.merge!(measurement_totals(repositories).as_h)
      result["repositories"] = JSON::Any.new(repositories.size.to_i64)
      File.write(File.join(ROWS, "#{tech}-audit-sample.json"), sample(unmatched[tech]).to_pretty_json + "\n")
      JSON::Any.new(result)
    end
    revision = IO::Memory.new
    command("git", ["log", "-1", "--format=%H", "--", "src", "shard.yml", "shard.lock"], output: revision)
    previous = JSON.parse(File.read(RESULTS)) if File.exists?(RESULTS)
    same_snapshot = previous && previous["analyzer_revision"].as_s == revision.to_s.strip && previous["repositories"].as_a.map { |row| pin(row) } == results.map { |row| pin(row) }
    measured_on = if previous && same_snapshot
                    previous["measured_on"].as_s
                  else
                    Time.utc.to_s("%F")
                  end
    data = JSON.parse({measured_on: measured_on, analyzer_revision: revision.to_s.strip, technologies: totals, repositories: results}.to_json)
    generated = "Measured: #{measured_on}. Analyzer source: `#{revision.to_s.strip}`.\n\nA technology measured on one repository is a single data point.\n\n" + table(totals, "Technology", repository_counts: true)
    generated += "\n\n" + table(results, "Repository") + "\n"
    generated += measurement_tables(totals, results)
    generated += "\n| Technology | Resolution claim | Marked endpoints | Share of code endpoints |\n| --- | --- | ---: | ---: |\n"
    totals.each do |row|
      row["claims"].as_h.each do |claim, mark|
        generated += "| #{row["name"]} | `#{claim}` | #{mark["count"]} | #{percent(mark["share"])} |\n"
      end
    end
    generated += "\n"
    repos.each do |repo|
      adjustment = repo["spec_prefix"]?.try { |prefix| " Spec rows are compared without the deployment `#{prefix.as_s}` prefix." } || ""
      adjustment += repo["exclude_paths"]?.try { |paths| " Outside this service: #{paths.as_a.map { |path| "`#{path.as_s}`" }.join(", ")}." } || ""
      generated += "- [#{repo["name"]}](#{repo["url"].as_s}/tree/#{repo["commit"].as_s}) · `#{repo["commit"].as_s}` · #{repo["technologies"].as_a.map { |tech| "`#{tech.as_s}`" }.join(", ")} · scope `#{repo["scope"].as_s}` · #{repo["specs"].as_a.map { |path| "`#{path.as_s}`" }.join(", ")}. #{repo["note"].as_s}#{adjustment}\n"
    end
    File.write(RESULTS, data.to_pretty_json + "\n")
    %w[index.md index.ko.md].each do |name|
      path = File.join("docs/content/usage/accuracy", name)
      content = File.read(path)
      raise "Missing scoreboard markers in #{path}" unless content.includes?("<!-- SCOREBOARD -->") && content.includes?("<!-- /SCOREBOARD -->")
      localized = generated
      if name.ends_with?(".ko.md")
        localized = generated.sub("A technology measured on one repository is a single data point.", "저장소 하나에서 측정한 기술은 단일 데이터 포인트입니다.")
      end
      File.write(path, content.sub(/<!-- SCOREBOARD -->.*<!-- \/SCOREBOARD -->/m, "<!-- SCOREBOARD -->\n\n#{localized}\n<!-- /SCOREBOARD -->"))
    end
    puts "Scoreboard written in #{(Time.instant - started).total_seconds.round(2)}s; per-row reports and audit samples: #{ROWS}."
  end
end

Scoreboard.run if ARGV.delete("--run-scoreboard")
