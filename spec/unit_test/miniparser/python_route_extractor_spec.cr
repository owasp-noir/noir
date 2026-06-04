require "spec"
require "../../../src/miniparsers/python_route_extractor"

describe Noir::PythonRouteExtractor do
  describe "scan_decorators" do
    it "extracts a @<var>.route decorator with its method tail" do
      decs = Noir::PythonRouteExtractor.scan_decorators(
        %(@app.route("/users", methods=["GET", "POST"]))
      )
      decs.size.should eq(1)
      decs[0].router_name.should eq("app")
      decs[0].path.should eq("/users")
      decs[0].extra_params.should contain("methods=")
    end

    it "extracts method-specific decorators and synthesizes the methods tail" do
      decs = Noir::PythonRouteExtractor.scan_decorators(%(@bp.post("/login")))
      decs.size.should eq(1)
      decs[0].router_name.should eq("bp")
      decs[0].path.should eq("/login")
      decs[0].extra_params.should eq("methods=['POST']")
    end

    it "recognizes every supported HTTP method decorator" do
      %w[get post put patch delete head options trace].each do |method|
        decs = Noir::PythonRouteExtractor.scan_decorators(%(@r.#{method}("/p")))
        decs.size.should eq(1)
        decs[0].extra_params.should eq("methods=['#{method.upcase}']")
      end
    end

    it "handles r-string and f-string path prefixes" do
      Noir::PythonRouteExtractor.scan_decorators(%(@app.route(r"/raw")))[0].path.should eq("/raw")
      Noir::PythonRouteExtractor.scan_decorators(%(@app.route(f"/fmt")))[0].path.should eq("/fmt")
    end

    it "recovers space-bearing paths from the original (unstripped) line" do
      stripped = %(@app.route("/withspace"))
      original = %(@app.route("/with space"))
      decs = Noir::PythonRouteExtractor.scan_decorators(stripped, original)
      decs[0].path.should eq("/with space")
    end

    it "returns an empty array when no decorator is present" do
      Noir::PythonRouteExtractor.scan_decorators("x = compute()").should be_empty
    end
  end

  describe "scan_blueprint" do
    it "detects a module-qualified Blueprint assignment with url_prefix" do
      result = Noir::PythonRouteExtractor.scan_blueprint(
        %(admin=flask.Blueprint("admin", __name__, url_prefix="/admin")),
        ["flask"]
      )
      result.should_not be_nil
      name, prefix = result.not_nil!
      name.should eq("admin")
      prefix.should eq("/admin")
    end

    it "detects a bare Blueprint assignment without a prefix" do
      result = Noir::PythonRouteExtractor.scan_blueprint(
        %(api=Blueprint("api", __name__)),
        ["flask"]
      )
      result.should_not be_nil
      name, prefix = result.not_nil!
      name.should eq("api")
      prefix.should eq("")
    end

    it "tolerates a type annotation on the assignment target" do
      result = Noir::PythonRouteExtractor.scan_blueprint(
        %(bp:Blueprint=sanic.Blueprint("bp", url_prefix="/v1")),
        ["sanic"]
      )
      result.should_not be_nil
      result.not_nil![0].should eq("bp")
      result.not_nil![1].should eq("/v1")
    end

    it "returns nil when the line is not a Blueprint assignment" do
      Noir::PythonRouteExtractor.scan_blueprint("x = SomethingElse()", ["flask"]).should be_nil
    end
  end

  describe "find_def_line" do
    it "finds the def immediately below a decorator" do
      lines = ["@app.route('/x')", "def handler():"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "skips chained decorators, comments and blank lines" do
      lines = [
        "@app.route('/x')",
        "@login_required",
        "# a comment",
        "",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(4)
    end

    it "walks past a multi-line decorator header" do
      lines = [
        "@app.route(",
        "    '/x',",
        "    methods=['GET']",
        ")",
        "def handler():",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(4)
    end

    it "matches a class declaration too" do
      lines = ["@register", "class MyView:"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(1)
    end

    it "walks upward to the enclosing def when direction is :up" do
      lines = [
        "def existing():",
        "    pass",
        "@app.get('/x')",
      ]
      Noir::PythonRouteExtractor.find_def_line(lines, 2, :up).should eq(0)
    end

    it "returns the original index when nothing matches" do
      lines = ["@app.route('/x')", "x = 1"]
      Noir::PythonRouteExtractor.find_def_line(lines, 0).should eq(0)
    end
  end
end
