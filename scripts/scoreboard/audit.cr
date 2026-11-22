module Scoreboard
  LABELS = "scripts/scoreboard/labels.tsv"

  record Label, repository : String, technology : String, commit : String, side : String, method : String, url : String, verdict : String

  VERDICTS = {
    "code-only" => %w[real false_positive wrong_address cannot_tell],
    "spec-only" => %w[miss not_served wrong_address covered cannot_tell],
  }

  def read_labels(io : IO) : Array(Label)
    header = %w[repository technology commit side method url verdict source evidence]
    raise "Unexpected audit label header" unless io.gets.try(&.split('\t')) == header
    labels = [] of Label
    io.each_line.with_index(2) do |line, number|
      fields = line.split('\t')
      unless fields.size == header.size && fields.none?(&.strip.empty?) &&
             fields[2].matches?(/\A[0-9a-f]{40}\z/) && fields[7].matches?(/:\d*[1-9]\d*\z/) &&
             VERDICTS[fields[3]]?.try(&.includes?(fields[6]))
        raise "Invalid audit label at line #{number}"
      end
      labels << Label.new(fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6])
    end
    identities = labels.uniq { |l| {l.repository, l.technology, l.commit, l.side, l.method, l.url} }
    raise "Duplicate audit label" unless identities.size == labels.size
    labels
  end

  # Each repository/technology is a stratum. Expand its own decided sample
  # before summing: two repositories may have very different sampling rates.
  private class AuditSide
    getter sample_size = 0
    getter population = 0
    @sampled = 0
    @labelled = 0
    getter projection : Float64? = 0.0
    getter verdicts : Hash(String, Int32)

    def initialize(@side : String, @stale : Int32)
      @verdicts = VERDICTS[@side].to_h { |v| {v, 0} }
      @marked = Hash(String, Int32).new
      @marked = @verdicts.dup if @side == "code-only"
    end

    def count(repository, rows, labels)
      population = repository[@side.tr("-", "_")].as_i
      @population += population
      @sampled += rows.size
      decided = positive = 0
      rows.group_by { |r| {r["method"].as_s, r["url"].as_s} }.each do |address, copies|
        # An address-only label cannot distinguish multiple sampled rows.
        label = copies.size == 1 ? labels[address]? : nil
        copies.each do |row|
          row.as_h["verdict"] = JSON::Any.new(label.try(&.verdict))
        end
        next unless label
        verdict = label.verdict
        @labelled += 1
        @stale -= 1
        @verdicts[verdict] += 1
        @marked[verdict] += 1 if @side == "code-only" && copies.first["marked"].as_bool
        next if verdict == "cannot_tell"
        decided += 1
        positive += 1 if @side == "code-only" ? verdict == "real" : {"miss", "wrong_address"}.includes?(verdict)
      end
      @sample_size += decided
      return if population.zero?
      @projection = @projection.try { |sum| sum + population * (positive.to_f / decided) unless decided.zero? }
    end

    def estimate(value)
      {value: value, sample_size: @sample_size, unlabelled: @sampled - @labelled, cannot_tell: @verdicts["cannot_tell"]}
    end

    def report
      result = JSON.parse({sampled: @sampled, labelled: @labelled, unlabelled: @sampled - @labelled,
                           stale: @stale, verdicts: @verdicts}.to_json)
      result.as_h["marked_by_verdict"] = JSON.parse(@marked.to_json) if @side == "code-only"
      result
    end
  end

  # The caller scopes labels to the group being reported, including old pins.
  # Only exact keys at the current pin count; everything else stays stale.
  def audit_summary(repositories, samples, labels : Array(Label))
    sides = VERDICTS.keys.to_h do |side|
      candidates = labels.select { |l| l.side == side }
      counter = AuditSide.new(side, candidates.size)
      repositories.each do |repo|
        tech = repo["technology"].as_s
        name = repo["name"].as_s
        rows = samples[tech].select { |r| r["repository"] == name && r["side"] == side }
        current = candidates.select { |l| l.repository == name && l.technology == tech && l.commit == repo["commit"].as_s }
        counter.count(repo, rows, current.to_h { |l| { {l.method, l.url}, l } })
      end
      {side, counter}
    end
    code = sides["code-only"]
    doc = sides["spec-only"]
    matched = repositories.sum(&.["matched"].as_i)
    reported = matched + code.population
    precision = code.projection.try { |real| (matched + real) / reported unless reported.zero? }
    recall = doc.projection.try { |misses| matched / (matched + misses) unless (matched + misses).zero? }
    JSON.parse({matched: matched, spec_only: doc.population, code_only: code.population,
                marked_matched: repositories.sum(&.["marked_matched"].as_i), marked_code_only: repositories.sum(&.["marked_code_only"].as_i),
                code_sample: code.report, spec_sample: doc.report,
                estimated_precision: code.estimate(precision), estimated_recall: doc.estimate(recall)}.to_json)
  end

  def audit_table(rows) : String
    String.build do |io|
      io << "\n| Scope | Estimated precision | Estimated recall | Marked matched / code-only |\n| --- | ---: | ---: | ---: |\n"
      rows.each do |name, audit|
        io << "| #{name} |"
        %w[estimated_precision estimated_recall].each do |metric|
          e = audit[metric]
          io << " #{percent(e["value"])} (n=#{e["sample_size"]}, #{e["unlabelled"]} unlabelled, #{e["cannot_tell"]} undecided) |"
        end
        io << " #{audit["marked_matched"]} / #{audit["marked_code_only"]} |\n"
      end
    end
  end
end
