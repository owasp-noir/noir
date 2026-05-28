require "file_utils"
require "benchmark"

# Target directory for mock codebase
BENCHMARK_DIR = "tmp/benchmark_fixtures"
RUNS          = 3

def generate_mock_codebase
  puts "Generating mock codebase in #{BENCHMARK_DIR}..."
  FileUtils.mkdir_p(BENCHMARK_DIR)

  # 1. Generate Express.js Javascript mock files (100 files, 15 routes each)
  FileUtils.mkdir_p("#{BENCHMARK_DIR}/javascript")
  100.times do |i|
    content = String.build do |str|
      str << "const express = require('express');\n"
      str << "const app = express();\n"
      15.times do |j|
        str << "app.get('/api/js/file#{i}/route#{j}', (req, res) => res.send('ok'));\n"
        str << "app.post('/api/js/file#{i}/route#{j}', (req, res) => res.send('ok'));\n"
      end
    end
    File.write("#{BENCHMARK_DIR}/javascript/mock_#{i}.js", content)
  end

  # 2. Generate Flask Python mock files (100 files, 15 routes each)
  FileUtils.mkdir_p("#{BENCHMARK_DIR}/python")
  100.times do |i|
    content = String.build do |str|
      str << "from flask import Flask\n"
      str << "app = Flask(__name__)\n"
      15.times do |j|
        str << "@app.route('/api/py/file#{i}/route#{j}', methods=['GET', 'POST'])\n"
        str << "def r_#{i}_#{j}():\n"
        str << "    return 'ok'\n"
      end
    end
    File.write("#{BENCHMARK_DIR}/python/mock_#{i}.py", content)
  end

  # 3. Generate Gin Go mock files (100 files, 15 routes each)
  FileUtils.mkdir_p("#{BENCHMARK_DIR}/go")
  100.times do |i|
    content = String.build do |str|
      str << "package main\n"
      str << "import \"github.com/gin-gonic/gin\"\n"
      str << "func SetupRouter#{i}() *gin.Engine {\n"
      str << "    r := gin.Default()\n"
      15.times do |j|
        str << "    r.GET(\"/api/go/file#{i}/route#{j}\", func(c *gin.Context) {})\n"
        str << "    r.POST(\"/api/go/file#{i}/route#{j}\", func(c *gin.Context) {})\n"
      end
      str << "    return r\n"
      str << "}\n"
    end
    File.write("#{BENCHMARK_DIR}/go/mock_#{i}.go", content)
  end

  # 4. Generate Sinatra Ruby mock files (100 files, 15 routes each)
  FileUtils.mkdir_p("#{BENCHMARK_DIR}/ruby")
  100.times do |i|
    content = String.build do |str|
      str << "require 'sinatra'\n"
      15.times do |j|
        str << "get '/api/rb/file#{i}/route#{j}' do\n"
        str << "  'ok'\n"
        str << "end\n"
        str << "post '/api/rb/file#{i}/route#{j}' do\n"
        str << "  'ok'\n"
        str << "end\n"
      end
    end
    File.write("#{BENCHMARK_DIR}/ruby/mock_#{i}.rb", content)
  end

  puts "Mock codebase generated: 400 files with 6,000 endpoint definitions total."
end

def cleanup_mock_codebase
  if Dir.exists?(BENCHMARK_DIR)
    puts "Cleaning up mock codebase..."
    FileUtils.rm_rf(BENCHMARK_DIR)
  end
end

def measure_run(binary : String, args : Array(String)) : Float64
  start_time = Time.instant
  status = Process.run(
    binary,
    args: args,
    output: Process::Redirect::Close,
    error: Process::Redirect::Close
  )
  end_time = Time.instant
  raise "Execution failed for #{binary}" unless status.success?
  (end_time - start_time).to_f
end

def run_benchmarks(global_bin : String, local_bin : String, extra_args : Array(String))
  global_times = [] of Float64
  local_times = [] of Float64

  scan_args = ["scan", BENCHMARK_DIR] + extra_args

  unless extra_args.empty?
    puts "Forwarding extra scan arguments: #{extra_args.join(" ")}"
  end

  puts "\nWarming up cache (performing 1 unrecorded run)..."
  measure_run(global_bin, scan_args)
  measure_run(local_bin, scan_args)

  puts "Running benchmarks (performing #{RUNS} runs for each)..."

  RUNS.times do |run|
    puts "--- Run #{run + 1} / #{RUNS} ---"

    # Global binary
    print "  Global (noir)... "
    t_global = measure_run(global_bin, scan_args)
    global_times << t_global
    puts "#{t_global.round(4)}s"

    # Local binary
    print "  Local (./bin/noir)... "
    t_local = measure_run(local_bin, scan_args)
    local_times << t_local
    puts "#{t_local.round(4)}s"
  end

  # Calculate stats
  avg_global = global_times.sum / RUNS
  avg_local = local_times.sum / RUNS
  diff = avg_global - avg_local
  percent = (diff / avg_global) * 100

  # Format output
  puts "\n"
  puts "=" * 60
  puts "                    NOIR BENCHMARK RESULTS"
  puts "=" * 60
  puts "Mock Codebase Size: 400 files, ~6,000 endpoints"
  puts "\nDetailed Runs:"

  puts "| Binary | " + (1..RUNS).map { |r| "Run #{r}" }.join(" | ") + " | Average |"
  puts "|--------|" + (1..RUNS).map { "-------" }.join("|") + "|---------|"

  global_run_strs = global_times.map { |t| "#{t.round(3)}s" }.join(" | ")
  puts "| Global (noir) | #{global_run_strs} | #{avg_global.round(3)}s |"

  local_run_strs = local_times.map { |t| "#{t.round(3)}s" }.join(" | ")
  puts "| Local (./bin/noir) | #{local_run_strs} | #{avg_local.round(3)}s |"

  puts "\nConclusion:"
  if diff > 0
    puts "  Local build (./bin/noir) is #{percent.round(1)}% FASTER than Global (noir)."
  elsif diff < 0
    puts "  Global (noir) is #{(-percent).round(1)}% FASTER than Local (./bin/noir)."
  else
    puts "  Both binaries performed identically."
  end
  puts "=" * 60
end

# Find binaries
global_bin = Process.find_executable("noir")
unless global_bin
  STDERR.puts "Error: Global 'noir' binary not found in PATH."
  STDERR.puts "Please install noir globally before running benchmarks."
  exit 1
end

local_bin = "./bin/noir"
unless File.exists?(local_bin)
  STDERR.puts "Error: Local binary '#{local_bin}' not found."
  STDERR.puts "Please run `just build-release` first."
  exit 1
end

begin
  generate_mock_codebase
  run_benchmarks(global_bin, local_bin, ARGV)
ensure
  cleanup_mock_codebase
end
