require "spec"
require "../../../src/miniparsers/python_route_extractor_ts"

describe Noir::TreeSitterPythonRouteExtractor do
  it "extracts only executed request reads, including multiline calls and interpolation" do
    source = <<-PY
      async def handle(request):
          """request.headers.get('docstring')"""
          example = 'request.query_params.get("fake")'
          # request.cookies['comment']
          other_request.query_params.get('other')
          q = request.query_params.get(
              "real"
          )
          header = request.headers['x-' 'token']
          cookie = f"session {request.cookies.get('session')}"
          dynamic = request.query_params.get(f"key-{q}")
          return q, header, cookie
      PY

    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "request").should eq([
      {"real", "query"}, {"x-token", "header"}, {"session", "cookie"},
    ])
  end

  it "follows JSON assignments and keeps dictionary parameters separate" do
    source = <<-PY
      async def handle(request, payload):
          example = "body = await request.json()"
          body: dict = await request.json()
          a = body['first']; b = body.get('second')
          c = payload.get('direct')
          q = request.query_params.getlist('q')
          return a, b, c, q
      PY

    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "request").should eq([
      {"first", "json"}, {"second", "json"}, {"q", "query"},
    ])
    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "payload", dictionary: true).should eq([
      {"direct", "json"},
    ])
    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "missing").should be_empty
  end

  it "separates request names from dictionary mode in memo keys" do
    source = <<-PY
      async def handle(false, true):
          return false.get('body'), true.query_params.get('query')
      PY
    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "false", dictionary: true).should eq([
      {"body", "json"},
    ])
    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "true").should eq([
      {"query", "query"},
    ])
  end

  it "bounds nested parentheses when reading request keys" do
    depth = Noir::TreeSitter::MAX_AST_DEPTH + 10
    source = "request.query_params.get(#{"(" * depth}'q'#{")" * depth})"
    Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "request").should be_empty
  end

  it "does not invent empty request keys at the traversal depth boundary" do
    (-4..0).each do |offset|
      depth = Noir::TreeSitter::MAX_AST_DEPTH + offset
      {"'q'" => "q", "'q' 'r'" => "qr"}.each do |literal, expected|
        source = "request.query_params.get(#{"(" * depth}#{literal}#{")" * depth})"
        Noir::TreeSitterPythonRouteExtractor.extract_request_params(source, "request").each do |name, type|
          name.should eq(expected)
          type.should eq("query")
        end
      end
    end
    Noir::TreeSitterPythonRouteExtractor.extract_request_params("request.query_params.get('' '')", "request").should eq([
      {"", "query"},
    ])
  end

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
      {"/lookup", ["GET", "QUERY"], "lookup_record"},
      {"/search", ["QUERY"], "search_record"},
      {"/sign", ["GET", "POST"], "sign_sample"},
      {"/update_record", ["POST"], "update_record"},
    ])

    decos.each(&.router_name.should eq("app"))
  end

  it "finds Blueprint declarations with their url_prefix" do
    source = <<-PY
      from flask import Blueprint
      import flask

      bare_bp = Blueprint("bare", __name__, url_prefix="/bare")
      prefixed = flask.Blueprint("pref", __name__, url_prefix="/api/v1")
      dotted = my_pkg.flask.Blueprint("d", __name__, url_prefix="/dot")
      ignored = other.Blueprint("x", __name__, url_prefix="/nope")
      PY

    # `my_pkg.flask` is accepted because the full dotted text is in
    # the allowlist, preserving the legacy procedural behaviour.
    bps = Noir::TreeSitter.parse_python(source) { |root| Noir::TreeSitterPythonRouteExtractor.extract_blueprints_from(root, source, ["flask", "my_pkg.flask"]) }
    bps.map { |b| {b.name, b.prefix} }.should eq([
      {"bare_bp", "/bare"},
      {"prefixed", "/api/v1"},
      {"dotted", "/dot"},
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

  # f-strings used to silently drop their `{expr}` interpolation
  # nodes, turning `f"/api/{VERSION}/items"` into `"/api//items"`
  # (and after optimizer normalization, `"/api/items"`) — the
  # user's path template lost a segment without any indication.
  # A field naming a module-level string constant is that string;
  # any other keeps its source text as the `{expr}` placeholder so
  # the downstream path-param extractor picks it up and the
  # rendered URL faithfully reflects the route.
  it "reads an f-string field naming a module string and keeps any other as an {expr} placeholder" do
    source = <<-PY
      VERSION = "v2"
      @app.route(f"/api/{VERSION}/items")
      def x(): pass

      @app.route(f"/users/{user_id}/posts/{post_id}")
      def y(): pass
      PY

    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    decos.map(&.path).should eq([
      "/api/v2/items",
      "/users/{user_id}/posts/{post_id}",
    ])
  end

  it "reads a path spelled as a module constant, a concatenation or adjacent literals" do
    source = <<-PY
      API = "/api"
      USERS = API + "/users"
      TWICE = "/a"
      TWICE = "/b"

      @app.route(USERS)
      def users(): pass

      @app.get(API + "/ping")
      def ping(): pass

      @app.post("/hooks" "/github")
      def hook(): pass

      @app.route(TWICE)
      def rebound(): pass

      @app.route(imported.PATH)
      def unread(): pass
      PY

    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    decos.map { |d| {d.path, d.def_name} }.should eq([
      {"/api/users", "users"},
      {"/api/ping", "ping"},
      {"/hooks/github", "hook"},
    ])
  end

  it "leaves plain strings unaffected (no interpolation children)" do
    source = <<-PY
      @app.route("/static")
      def x(): pass
      PY
    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
    decos.map(&.path).should eq(["/static"])
  end

  it "reads a list of paths, the route= keyword and bare @route when asked" do
    source = <<-PY
      @http.route(["/shop", "/shop/page/<int:page>"], type="http", csrf=False)
      def shop(self): pass

      @http.route(route=["/a", "/b"])
      def ab(self): pass

      @route("/bare", auth="none")
      def bare(self): pass
      PY
    decos = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, bare_route: true)
    decos.map(&.paths).should eq([["/shop", "/shop/page/<int:page>"], ["/a", "/b"], ["/bare"]])
    decos[0].keywords.should eq({"type" => "http", "csrf" => "False"})
    decos[2].router_name.should eq("")

    Noir::TreeSitterPythonRouteExtractor.extract_decorations(source).map(&.path).should eq(["/shop", "/a"])
  end

  it "does not read a positional verb list as paths" do
    source = <<-PY
      @app.route(PATH, ["GET", "POST"])
      def handler(): pass
      PY
    Noir::TreeSitterPythonRouteExtractor.extract_decorations(source).should be_empty
  end

  it "keeps a decorator without a path only when pathless" do
    source = <<-PY
      @frappe.whitelist(allow_guest=True, methods=["POST"])
      def ping(): pass
      PY
    attrs = {"whitelist" => "GET"}
    Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, ["frappe"], attrs).should be_empty
    deco = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, ["frappe"], attrs, pathless: true).first
    {deco.path, deco.def_name, deco.methods, deco.keywords["allow_guest"]}.should eq({"", "ping", ["POST"], "True"})
  end
end
