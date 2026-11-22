require "../func_spec"
require "../../../src/utils/url_path"

private def runtime_route(app : String, method : String, path : String, *, manifest : Bool = false, regex : Bool = false) : String
  # Express serializes a flagless anchored RegExp with delimiters. Only
  # compare its body with another regex row, preserving other regex syntax.
  if app == "express" && manifest && path.starts_with?("/^") && path.ends_with?("$/")
    path = path[2...-2].gsub("\\/", "/")
    regex = true
  end
  return "#{method} regex #{path}" if regex

  # A FastAPI :path converter consumes slashes, unlike a single path slot.
  path = path.gsub(/\{(\w+):path\}/, "{*\\1}") if app == "fastapi"
  # In Express an optional whole /:name segment may be written {/:name}.
  path = path.gsub(/\{\/:([A-Za-z_]\w*)\}(?=\/|$)/, "/:\\1?") if app == "express"
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
      served = JSON.parse(File.read(manifest)).as_a.flat_map do |row|
        method = row["method"].as_s
        # ALL/ANY must cover every verb Noir emits for an all-methods row.
        methods = method.in?("ALL", "ANY") ? %w[GET HEAD POST PUT PATCH DELETE OPTIONS] : [method]
        methods.map { |verb| runtime_route(name, verb, row["path"].as_s, manifest: true) }
      end.to_set
      served.should_not be_empty

      tester = FunctionalTester.new(name, nil, nil, {
        "base" => YAML::Any.new([YAML::Any.new("#{root}/src")]),
      })
      # A library route with no observed registration is still visible to
      # scan users. It supplies no evidence for a running server's table.
      reported = Set(String).new
      excluded = [] of String
      tester.endpoints.each do |ep|
        next unless ep.protocol == "http"
        route = runtime_route(name, ep.method, ep.url, regex: ep.kind == "regex")
        if ep.resolution.try(&.["registration"]?) == "unresolved"
          excluded << route
        else
          reported << route
        end
      end
      puts "runtime reference #{name}: excluded #{excluded.size} HTTP rows with unresolved registration"

      gaps = (served - reported).map { |route| "missed #{route}" }.to_set
      (reported - served).each { |route| gaps << "extra #{route}" }
      baseline = "#{root}/known-gaps.txt"
      known = File.read_lines(baseline).reject { |line| line.empty? || line.starts_with?('#') }.to_set

      changes = (gaps - known).to_a.sort.map { |line| "New: #{line}" }
      (excluded.to_set & served).to_a.sort.each { |route| changes << "Served but registration unresolved: #{route}" }
      (known - gaps).to_a.sort.each { |line| changes << "Stale: #{line}" }
      fail "#{baseline}\n#{changes.join('\n')}" unless changes.empty?
    end
  end
end
