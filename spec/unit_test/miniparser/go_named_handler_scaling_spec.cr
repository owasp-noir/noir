require "../../spec_helper"
require "../../../src/miniparsers/go_named_handler"

# One function binding thousands of closures and then registering a route on
# each (`h0 := func(...)` ... `r.Get("/p0", h0)`). Finding a route's local
# binding walked back line by line from the route to its function's head, once
# for the bound call and once more for the closure row: 8000 routes took ~16x
# what 2000 did. The file's bindings are indexed once now, so 4x the routes
# must cost about 4x the time.
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
  elapsed = Time.measure do
    named = Noir::GoNamedHandler.new(source, "main.go", extracted)
    handlers = extracted.map { |route| named.handler_for(route) }
  end
  last = handlers.last.not_nil!
  last.name.should eq("h#{routes - 1}")
  last.line.should eq(routes + 4)
  elapsed
end

describe "Go named-handler local binding scaling" do
  it "resolves locally bound closures in linear time" do
    small = (0...3).min_of { timed_handlers(2000) }
    large = (0...3).min_of { timed_handlers(8000) }
    # Linear is ~4x; the per-route walks were ~16x.
    (large / {small, 1.millisecond}.max).should be < 10.0
  end
end
