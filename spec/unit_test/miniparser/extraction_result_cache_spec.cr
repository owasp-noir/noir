require "spec"
require "../../../src/miniparsers/extraction_result_cache"
require "../../../src/miniparsers/python_route_extractor_ts"

describe Noir::ExtractionResultCache do
  it "fingerprints equal content identically" do
    a = "hello world"
    b = String.build { |io| io << "hello world" }
    Noir::ExtractionResultCache.source_fingerprint(a).should eq(
      Noir::ExtractionResultCache.source_fingerprint(b)
    )
  end

  it "fingerprints different content differently" do
    Noir::ExtractionResultCache.source_fingerprint("a").should_not eq(
      Noir::ExtractionResultCache.source_fingerprint("b")
    )
  end
end

describe Noir::TreeSitterPythonRouteExtractor do
  it "returns the same decorations on a second call (memo hit)" do
    source = <<-PY
      from flask import Flask
      app = Flask(__name__)

      @app.route("/ping")
      def ping():
          return "ok"
      PY

    first = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    second = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    first.should eq(second)
    first.size.should eq(1)
    first[0].path.should eq("/ping")
  end

  it "extracts decorations and blueprints in one combined call" do
    source = <<-PY
      from flask import Flask, Blueprint
      app = Flask(__name__)
      api = Blueprint("api", __name__, url_prefix="/api")

      @app.route("/")
      def index():
          return "hi"

      @api.get("/items")
      def items():
          return []
      PY

    decos, bps = Noir::TreeSitterPythonRouteExtractor.extract_decorations_and_blueprints(
      source, ["flask"]
    )
    decos.map(&.path).sort!.should eq(["/", "/items"])
    bps.map(&.name).should eq(["api"])
    bps[0].prefix.should eq("/api")

    # Solo calls must hit the same memo entries.
    Noir::TreeSitterPythonRouteExtractor.extract_decorations(source).map(&.path).sort!.should eq(["/", "/items"])
    Noir::TreeSitterPythonRouteExtractor.extract_blueprints(source, ["flask"]).map(&.name).should eq(["api"])
  end
end
