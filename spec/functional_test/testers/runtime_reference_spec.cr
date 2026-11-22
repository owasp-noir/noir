require "../func_spec"
require "../../../src/utils/url_path"

private def runtime_route(method : String, path : String) : String
  "#{method} #{Noir::URLPath.unify_path_placeholders(path)}"
end

describe "runtime reference", tags: "functional" do
  %w[express hono fastapi gin].each do |name|
    root = "spec/runtime_reference/apps/#{name}"
    manifest = "#{root}/routes.json"

    unless File.exists?(manifest)
      pending "#{name} needs #{manifest}"
      next
    end

    it "matches the registered HTTP routes for #{name}" do
      served = JSON.parse(File.read(manifest)).as_a.map do |row|
        runtime_route(row["method"].as_s, row["path"].as_s)
      end.to_set
      served.should_not be_empty

      tester = FunctionalTester.new(name, nil, nil, {
        "base" => YAML::Any.new([YAML::Any.new("#{root}/src")]),
      })
      reported = tester.endpoints.select { |ep| ep.protocol == "http" }
        .map { |ep| runtime_route(ep.method, ep.url) }.to_set

      gaps = (served - reported).map { |route| "missed #{route}" }.to_set
      (reported - served).each { |route| gaps << "extra #{route}" }
      baseline = "#{root}/known-gaps.txt"
      known = File.read_lines(baseline).reject { |line| line.empty? || line.starts_with?('#') }.to_set

      changes = (gaps - known).to_a.sort.map { |line| "New: #{line}" }
      (known - gaps).to_a.sort.each { |line| changes << "Stale: #{line}" }
      fail "#{baseline}\n#{changes.join('\n')}" unless changes.empty?
    end
  end
end
