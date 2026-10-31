require "json"
require "file_utils"

# How well `noir trace` alone answers access-log triage on large OSS apps:
# for each request in scripts/agent_bench/cases.json, does the top match
# name the declared route, the handler's file:line, and whether an
# anonymous caller gets through? The answer keys were built from source
# by hand, never from noir output.
#
# This is the number that predicted agent results in the #3135 benchmark:
# where it was low, agents using noir lost to agents reading source; where
# it was near 100%, they spent fewer calls for the same answers. It needs
# network access to clone the pinned commits (shallow, into tmp/).

CASES = "scripts/agent_bench/cases.json"
WORK  = "tmp/agent_bench"
NOIR  = ENV["NOIR_BIN"]? || "./bin/noir"

PLACEHOLDER = /\{[^}\/]+\}|<[^>\/]+>|:[A-Za-z_]\w*/

def normalize_route(route : String?) : String?
  return unless route
  path = route.sub(/\A[A-Z]+\s+/, "").sub("(.:format)", "")
  path = path.gsub(PLACEHOLDER, ":x").downcase
  path.size > 1 ? path.rchop('/') : path
end

def checkout(name : String, url : String, commit : String) : String
  dir = File.join(WORK, name)
  head = Process.run("git", ["-C", dir, "rev-parse", "HEAD"], output: :pipe, error: :close) { |p| p.output.gets_to_end.strip } rescue ""
  return dir if head == commit
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  [["init", "-q"], ["remote", "add", "origin", url], ["fetch", "-q", "--depth", "1", "origin", commit], ["checkout", "-q", "FETCH_HEAD"]].each do |args|
    status = Process.run("git", ["-C", dir] + args, output: :inherit, error: :inherit)
    abort "git #{args.first} failed for #{name}" unless status.success?
  end
  dir
end

def trace(report : String, request : String) : JSON::Any?
  line = Process.run(NOIR, ["trace", request, "--from", report, "-f", "jsonl", "--limit", "1"], output: :pipe, error: :close) { |p| p.output.gets }
  line ? JSON.parse(line) : nil
end

abort "#{NOIR} not found; run `just build-release` first" unless File.exists?(NOIR)
totals = {route: 0, handler: 0, auth: 0, n: 0}

JSON.parse(File.read(CASES))["repos"].as_a.each do |repo|
  name = repo["name"].as_s
  dir = checkout(name, repo["url"].as_s, repo["commit"].as_s)
  report = File.join(WORK, "#{name}.json")
  Process.run(NOIR, ["scan", dir, "-f", "json", "--ai-context", "--include", "callee", "--no-log", "-o", report], output: :close, error: :close)

  route_ok = handler_ok = auth_ok = 0
  misses = [] of String
  cases = repo["requests"].as_a
  cases.each do |c|
    row = trace(report, c["request"].as_s)
    endpoint = row.try(&.["endpoint"]?)
    expected = c["route"].as_s?
    # A catch-all (`/*unmatched_route`, an SPA fallback) is not a route
    # match, nor is a proxy prefix location (nginx `location /v1`), unless
    # the key names that route (`/contents/*`).
    wildcard = {"wildcard", "wildcard_ci", "prefix"}.includes?(row.try(&.["matched_by"]?.try(&.as_s)))
    matched = endpoint && (!wildcard || normalize_route(endpoint["url"].as_s) == normalize_route(expected)) ? endpoint : nil

    r = normalize_route(matched.try(&.["url"].as_s)) == normalize_route(expected)
    h = a = true
    if expected && matched
      if want = c["handler"]?.try(&.as_s?)
        file, _, line = want.rpartition(':')
        got = matched["handler"]?
        h = !!got && got.as_h? != nil && got["path"].as_s.ends_with?(file) && (got["line"].as_i? || -99).-(line.to_i).abs <= 2
      end
      guards = matched.dig?("ai_context", "guards").try(&.as_a?) || [] of JSON::Any
      a = guards.empty? == c["anonymous"].as_bool
    elsif expected
      h = a = false
    end
    route_ok += 1 if r
    handler_ok += 1 if h
    auth_ok += 1 if a
    misses << "  #{c["request"].as_s[0, 60]}  route=#{r} handler=#{h} auth=#{a}" unless r && h && a
  end
  n = cases.size
  puts "#{name.ljust(12)} route #{route_ok}/#{n}  handler #{handler_ok}/#{n}  auth #{auth_ok}/#{n}"
  misses.each { |m| puts m }
  totals = {route: totals[:route] + route_ok, handler: totals[:handler] + handler_ok, auth: totals[:auth] + auth_ok, n: totals[:n] + n}
end

puts "TOTAL        route #{totals[:route]}/#{totals[:n]}  handler #{totals[:handler]}/#{totals[:n]}  auth #{totals[:auth]}/#{totals[:n]}"
