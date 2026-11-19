require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/python/fastapi"

# One module with thousands of routes sharing a body model, a dependency and
# an unresolved (stdlib) annotation.
# Each route used to resolve them by rescanning the whole module, so 2x the
# routes cost ~5x the time; they are resolved once per module now.
private def timed_fastapi_scan(routes : Int32) : Tuple(Array(Endpoint), Time::Span)
  temp_dir = File.tempname("fastapi_scaling")
  CodeLocator.instance.clear_all
  source = String.build do |io|
    io << "from uuid import UUID\nfrom fastapi import Depends, FastAPI, Query\nfrom pydantic import BaseModel\n\napp = FastAPI()\n\n"
    io << "class Item(BaseModel):\n    name: str\n    price: float\n\n"
    io << "def pagination(limit: int = 10):\n    return limit\n\n"
    routes.times do |i|
      io << %(@app.post("/r#{i}/{item_id}")\n)
      io << "async def h#{i}(item_id: int, cid: UUID, item: Item, q: str = Query(None), page: int = Depends(pagination)):\n    return {}\n\n"
    end
  end
  path = File.join(temp_dir, "main.py")
  Dir.mkdir_p(temp_dir)
  File.write(path, source)
  CodeLocator.instance.register_file(path, source)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  endpoints = [] of Endpoint
  elapsed = measure_without_gc { endpoints = Analyzer::Python::FastAPI.new(options).analyze }
  {endpoints, elapsed}
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "FastAPI large-module scaling" do
  it "resolves per-route models and dependencies in linear time" do
    small, small_time = timed_fastapi_scan(1000)
    large, large_time = timed_fastapi_scan(2000)
    small_time = {small_time, timed_fastapi_scan(1000)[1]}.min
    large_time = {large_time, timed_fastapi_scan(2000)[1]}.min
    small.size.should eq(1000)
    large.size.should eq(2000)
    last = large.find! { |e| e.url == "/r1999/{item_id}" }
    last.params.map { |p| {p.name, p.param_type} }.should eq([
      {"cid", "query"}, {"name", "json"}, {"price", "json"}, {"q", "query"}, {"limit", "query"},
    ])
    # Linear is ~2x; the per-route rescans were ~5x.
    (large_time / {small_time, 1.millisecond}.max).should be < 3.5
  end
end
