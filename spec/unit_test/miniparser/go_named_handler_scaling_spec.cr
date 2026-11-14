require "../../spec_helper"
require "../../../src/miniparsers/go_named_handler"

# One function binding thousands of closures and then registering a route on
# each (`h0 := func(...)` ... `r.Get("/p0", h0)`). Finding a route's local
# binding walked back line by line from the route to its function's head, once
# for the bound call and once more for the closure row: 8000 routes took ~16x
# what 2000 did. The file's bindings are indexed once now, so 8x the routes
# must cost about 8x the time.
#
# TEMP (remove before merge): `gc_off` and the SCALING-DIAG lines exist only
# to read the Windows CI log.
private def timed_handlers(routes : Int32, gc_off : Bool = false) : Time::Span
  source = String.build do |io|
    io << "package main\n\nfunc main() {\n\tr := chi.NewRouter()\n"
    routes.times { |i| io << "\th#{i} := func(w http.ResponseWriter, r *http.Request) {}\n" }
    routes.times { |i| io << "\tr.Get(\"/p#{i}\", h#{i})\n" }
    io << "}\n"
  end
  extracted = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
  extracted.size.should eq(routes)
  handlers = [] of Handler?
  if gc_off
    GC.collect
    GC.disable
  end
  gc_before = GC.prof_stats.gc_no
  stats_before = GC.stats
  ctor = Time::Span.zero
  begin
    elapsed = Time.measure do
      started = Time.instant
      named = Noir::GoNamedHandler.new(source, "main.go", extracted)
      ctor = started.elapsed
      handlers = extracted.map { |route| named.handler_for(route) }
    end
  ensure
    GC.enable if gc_off
  end
  stats_after = GC.stats
  STDERR.puts "SCALING-DIAG gc=#{gc_off ? "off" : "on"} n=#{routes} ms=#{elapsed.total_milliseconds.round(2)} " \
              "ctor_ms=#{ctor.total_milliseconds.round(2)} collections=#{GC.prof_stats.gc_no - gc_before} " \
              "alloc_mb=#{((stats_after.total_bytes - stats_before.total_bytes) / 1_048_576).round(1)} " \
              "heap_mb=#{stats_before.heap_size // 1_048_576}->#{stats_after.heap_size // 1_048_576}"
  last = handlers.last.not_nil!
  last.name.should eq("h#{routes - 1}")
  last.line.should eq(routes + 4)
  elapsed
end

describe "Go named-handler local binding scaling" do
  it "resolves locally bound closures in linear time" do
    # Sizes alternate, so a slow stretch on a shared runner slows both rather
    # than only the large runs (Windows CI once read 11.3 off a 4x spread
    # timed as three small runs then three large).
    small = large = Time::Span::MAX
    5.times do
      small = {small, timed_handlers(1000)}.min
      large = {large, timed_handlers(8000)}.min
    end
    ratio = large / {small, 1.millisecond}.max
    off_small = off_large = Time::Span::MAX
    5.times do
      off_small = {off_small, timed_handlers(1000, gc_off: true)}.min
      off_large = {off_large, timed_handlers(8000, gc_off: true)}.min
    end
    off_ratio = off_large / {off_small, 1.millisecond}.max
    STDERR.puts "SCALING-DIAG ratio gc=on #{ratio.round(2)} gc=off #{off_ratio.round(2)}"
    # 8x the routes: linear measures ~8x, the per-route walks ~60x.
    ratio.should be < 22.0
  end
end
