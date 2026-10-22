# Times every detector's `detect` over a real codebase, so detector-side
# content-scanning work can be prioritised by measured cost instead of by
# counting `includes?` calls (most of which sit behind a cheap basename
# gate and never run).
#
#   crystal run --release scripts/detector_scan_cost.cr -- <path> [<path>...]
require "yaml"
require "../src/detector/detector"
require "../src/utils/media_filter"
require "../src/utils/text_file"

options = {
  "base"    => YAML::Any.new([YAML::Any.new(ARGV[0]? || ".")]),
  "debug"   => YAML::Any.new(false),
  "verbose" => YAML::Any.new(false),
  "color"   => YAML::Any.new(false),
  "nolog"   => YAML::Any.new(true),
}

detectors = [] of Detector
{% for sub in Detector.all_subclasses %}
  {% unless sub.abstract? %}
    instance = {{ sub }}.new(options)
    instance.set_name
    detectors << instance
  {% end %}
{% end %}

# Collect the file set the detect phase would see.
paths = [] of String
ARGV.each do |root|
  stack = [root]
  until stack.empty?
    dir = stack.pop
    begin
      Dir.each_child(dir) do |entry|
        full = File.join(dir, entry)
        info = File.info?(full, follow_symlinks: false)
        next if info.nil?
        if info.directory?
          next if DETECTOR_IGNORED_DIR_NAMES.includes?(entry)
          stack << full
          next
        end
        next unless info.file?
        next if MediaFilter.skip_check(full, info: info, sniff_binary: false)
        paths << full
      end
    rescue
      next
    end
  end
end

contents = {} of String => String
total_bytes = 0_i64
paths.each do |path|
  content = Noir::TextFile.read(path)
  next if content.to_slice.includes?(0_u8)
  contents[path] = content
  total_bytes += content.bytesize
rescue
  next
end

STDERR.puts "corpus: #{contents.size} files, #{total_bytes // 1024} KB"

# Two passes: the first warms the page/branch state, the second is scored.
timings = {} of String => Time::Span
applied = Hash(String, Int32).new(0)
scanned = Hash(String, Int64).new(0_i64)

2.times do |round|
  detectors.each do |detector|
    hits = 0
    bytes = 0_i64
    elapsed = Time.measure do
      contents.each do |path, content|
        next unless detector.applicable?(path)
        hits += 1
        bytes += content.bytesize
        detector.detect(path, content)
      end
    end
    next unless round == 1
    timings[detector.name] = elapsed
    applied[detector.name] = hits
    scanned[detector.name] = bytes
  end
end

puts "#{"detector".ljust(30)} #{"ms".rjust(9)} #{"files".rjust(7)} #{"MB seen".rjust(9)}"
timings.to_a.sort_by { |(_, span)| -span.total_milliseconds }.first(40).each do |name, span|
  puts "#{name.ljust(30)} #{span.total_milliseconds.round(1).to_s.rjust(9)} " \
       "#{applied[name].to_s.rjust(7)} #{(scanned[name] / 1_048_576.0).round(1).to_s.rjust(9)}"
end
puts "-" * 60
puts "#{"TOTAL".ljust(30)} #{timings.values.sum(&.total_milliseconds).round(1).to_s.rjust(9)}"
