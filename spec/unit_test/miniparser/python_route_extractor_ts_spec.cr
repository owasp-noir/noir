require "spec"
require "../../../src/miniparsers/python_route_extractor_ts"
require "../../../src/miniparsers/python_route_extractor"

# Compares the tree-sitter Python route extractor against the existing
# regex-based extractor on real fixtures and on edge cases the regex
# extractor is known to mishandle.
describe Noir::TreeSitterPythonRouteExtractor do
  it "extracts every route in the bundled Flask fixture" do
    path = File.expand_path("../../../functional_test/fixtures/python/flask/app.py", __FILE__)
    source = File.read(path)

    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)

    triples = decos.map { |d| {d.path, d.methods.sort, d.def_name} }.sort_by!(&.[0])
    triples.should eq([
      {"/", ["GET"], "index"},
      {"/cookie", ["GET"], "cookie_test"},
      {"/create_record", ["PUT"], "create_record"},
      {"/delete_record", ["DELETE"], "delete_record"},
      {"/get_ip", ["GET"], "json_sample"},
      {"/login", ["POST"], "login_sample"},
      {"/sign", ["GET", "POST"], "sign_sample"},
    ])

    decos.each(&.router_name.should eq("app"))
  end

  it "finds Blueprint declarations with their url_prefix" do
    source = <<-PY
      from flask import Blueprint
      import flask

      bare_bp = Blueprint("bare", __name__, url_prefix="/bare")
      prefixed = flask.Blueprint("pref", __name__, url_prefix="/api/v1")
      ignored = other.Blueprint("x", __name__, url_prefix="/nope")
      PY

    bps = Noir::TreeSitterPythonRouteExtractor.extract_blueprints(source, ["flask"])
    bps.map { |b| {b.name, b.prefix} }.should eq([
      {"bare_bp", "/bare"},
      {"prefixed", "/api/v1"},
    ])
  end

  it "handles decorators split across multiple lines (regex extractor misses this)" do
    source = <<-PY
      @app.route(
          "/multiline",
          methods=["GET", "POST"],
      )
      def multi():
          pass
      PY

    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    decos.size.should eq(1)
    decos[0].path.should eq("/multiline")
    decos[0].methods.sort.should eq(["GET", "POST"])
    decos[0].def_name.should eq("multi")

    # Confirm the legacy regex extractor does miss it — this is the
    # tree-sitter port's first concrete accuracy win.
    regex_hits = source.each_line.flat_map do |line|
      Noir::PythonRouteExtractor.scan_decorators(line.strip, line).map(&.path)
    end.to_a
    regex_hits.should_not contain("/multiline")
  end

  it "is at parity with the regex extractor on single-line decorators" do
    path = File.expand_path("../../../functional_test/fixtures/python/flask/app.py", __FILE__)
    source = File.read(path)

    ts_paths = Noir::TreeSitterPythonRouteExtractor
      .extract_decorations(source)
      .map(&.path).sort!

    regex_paths = source.each_line.flat_map do |line|
      Noir::PythonRouteExtractor.scan_decorators(line.strip, line).map(&.path)
    end.to_a.sort

    ts_paths.should eq(regex_paths)
  end

  it "recognises method-specific decorators like @bp.get(\"/x\")" do
    source = <<-PY
      @bp.get("/items")
      def list_items():
          pass

      @bp.post("/items")
      def create_item():
          pass
      PY

    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    decos.map { |d| {d.path, d.methods, d.def_name} }.should eq([
      {"/items", ["GET"], "list_items"},
      {"/items", ["POST"], "create_item"},
    ])
  end
end
