require "../../spec_helper"
require "../../../src/miniparsers/go_named_handler"

# One function binding thousands of closures and then registering a route on
# each (`h0 := func(...)` ... `r.Get("/p0", h0)`). Finding a route's local
# binding walked back line by line from the route to its function's head, once
# for the bound call and once more for the closure row: 8000 routes took ~16x
# what 2000 did. The file's bindings are indexed once now, so 8x the routes
# must cost about 8x the time.
private def timed_handlers(routes : Int32) : Time::Span
  source = String.build do |io|
    io << "package main\n\nfunc main() {\n\tr := chi.NewRouter()\n"
    routes.times { |i| io << "\th#{i} := func(w http.ResponseWriter, r *http.Request) {}\n" }
    routes.times { |i| io << "\tr.Get(\"/p#{i}\", h#{i})\n" }
    io << "}\n"
  end
  extracted = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
  extracted.size.should eq(routes)
  handlers = [] of Handler?
  # The guard is about the lookup's complexity, not the collector's. The
  # 8000-route run allocates ~13 MB and takes a collection every time; the
  # 1000-route one allocates ~1.6 MB and takes none. On the Windows runner
  # that one collection cost ~127 ms against ~91 ms of work, so the ratio
  # read 19.4 with it and 8.2 without (macOS: 1-5 ms, no visible effect).
  # Start each run from a collected heap and keep the collector out of the
  # timed block. `GC.disable` counts, and the `ensure` re-enables it even if
  # the block raises, so the rest of the suite never runs with it off.
  GC.collect
  GC.disable
  begin
    elapsed = Time.measure do
      named = Noir::GoNamedHandler.new(source, "main.go", extracted)
      handlers = extracted.map { |route| named.handler_for(route) }
    end
  ensure
    GC.enable
  end
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
    # 8x the routes: linear measures ~8x, the per-route walks ~60x, with the
    # collector out of the timing. 22 sits about 2.7x from either side.
    (large / {small, 1.millisecond}.max).should be < 22.0
  end
end
