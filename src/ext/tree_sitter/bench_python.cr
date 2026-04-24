# Micro-benchmark comparing the legacy regex Python route extractor
# against the tree-sitter port on the bundled Flask fixture.
#
# Run with:
#   crystal run --release src/ext/tree_sitter/bench_python.cr
require "benchmark"
require "../../miniparsers/python_route_extractor"
require "../../miniparsers/python_route_extractor_ts"

fixture = File.expand_path("../../../../spec/functional_test/fixtures/python/flask/app.py", __FILE__)
source = File.read(fixture)
lines = source.lines

puts "fixture: #{fixture}"
puts "bytes:   #{source.bytesize}, lines: #{lines.size}"
puts

iterations = 2000

Benchmark.ips do |x|
  x.report("regex (line loop)") do
    iterations.times do
      lines.each do |line|
        Noir::PythonRouteExtractor.scan_decorators(line.strip, line)
      end
    end
  end

  x.report("tree-sitter (per file)") do
    iterations.times do
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    end
  end
end
