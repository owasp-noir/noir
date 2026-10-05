require "../../spec_helper"
require "../../../src/miniparsers/azure_functions_extractor"

private def triggers(path : String, content : String)
  Noir::AzureFunctionsExtractor.extract(path, content).map { |t| {t.name, t.route, t.methods, t.auth_level, t.line} }
end

describe Noir::AzureFunctionsExtractor do
  describe "C#" do
    it "reads positional methods, named Route and AuthLevel, and the function name" do
      triggers("F.cs", <<-CS).should eq [
        [Function(nameof(Api.GetItem))]
        public HttpResponseData GetItem(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "head", Route = "items/{id}")] HttpRequestData req) { }

        [FunctionName("Patch")]
        public static IActionResult Patch([HttpTrigger(AuthLevel = AuthorizationLevel.Admin, Methods = new[] { "patch" })] HttpRequest req) { }
        CS
        {"GetItem", "items/{id}", ["GET", "HEAD"], "anonymous", 3},
        {"Patch", nil, ["PATCH"], "admin", 6},
      ]
    end

    it "joins literal and nameof route parts, and skips a route it cannot resolve" do
      triggers("F.cs", <<-CS).should eq [{"Echo", "{region}/Echo", ["POST"], "anonymous", 2}]
        [Function(nameof(Echo))]
        public Task Echo([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{region}/" + nameof(Echo))] HttpRequestData r) { }
        [Function("FromConstant")]
        public Task C([HttpTrigger(AuthorizationLevel.Anonymous, Route = Routes.Items)] HttpRequestData r) { }
        CS
    end

    it "ignores commented-out triggers and a class named HttpTrigger" do
      triggers("F.cs", <<-CS).should eq [{nil, nil, [] of String, nil, 4}]
        public class HttpTrigger { public HttpTrigger(Ctx c) { } }
        // [Function("Old")] public Task Old([HttpTrigger(AuthorizationLevel.Anonymous)] HttpRequestData r) { }
        /* [HttpTrigger(AuthorizationLevel.Anonymous, Route = "gone")] */
        public Task Run([HttpTrigger] HttpRequestData r) { }
        CS
    end

    it "reads named constructor arguments and skips interpolated routes" do
      triggers("F.cs", <<-CS).should eq [{"A", nil, ["GET"], "anonymous", 2}]
        [Function("A")]
        public R A([HttpTrigger(authLevel: AuthorizationLevel.Anonymous, methods: new[] { "get" })] HttpRequestData r) { }
        [Function("B")]
        public R B([HttpTrigger(AuthorizationLevel.Anonymous, Route = $"{Routes.Base}/users")] HttpRequestData r) { }
        CS
    end

    it "keeps blanking comments after a verbatim string that ends in a backslash" do
      triggers("F.cs", <<-'CS').should be_empty
        const string P = @"C:\temp\";
        // [Function("Old")] public R Old([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "old")] HttpRequestData r) { }
        CS
    end

    it "does not lend one method's function name to the next trigger" do
      triggers("F.cs", <<-CS).map(&.[0]).should eq [nil]
        [Function("Timer")]
        public void Timer([TimerTrigger("0 * * * * *")] TimerInfo t) { }
        public void Test([HttpTrigger(AuthorizationLevel.Anonymous)] HttpRequestData r) { }
        CS
    end
  end

  describe "Python v2" do
    it "reads route, methods, auth level and function_name from the decorator stack" do
      triggers("function_app.py", <<-PY).should eq [
        import azure.functions as func
        app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

        @app.function_name(name="CreateOrder")
        @app.route(route="orders", methods=[func.HttpMethod.POST, "put"],
                   auth_level=func.AuthLevel.FUNCTION)
        async def create_order(req):
            pass

        @app.route()
        def status(req):
            pass

        @app.route("raw", methods=ALL)
        def raw(req):
            pass
        PY
        {"CreateOrder", "orders", ["POST", "PUT"], "function", 5},
        {"status", nil, [] of String, "anonymous", 10},
        {"raw", "raw", [] of String, "anonymous", 14},
      ]
    end

    it "only counts decorators on a FunctionApp or Blueprint" do
      triggers("app.py", <<-PY).map(&.[1]).should eq ["items"]
        import azure.functions as func
        from flask import Flask
        flask_app = Flask(__name__)
        bp = func.Blueprint()

        @flask_app.route("/flask")
        def flask_route():
            pass

        @bp.route(route="items")
        def items(req):
            pass
        PY
    end

    it "ignores Flask blueprints, docstrings and comments inside decorator arguments" do
      triggers("app.py", <<-PY).should eq [{"items", "items", ["GET"], nil, 12}]
        import azure.functions as func
        from flask import Blueprint
        admin = Blueprint("admin", __name__)
        app = func.FunctionApp()

        @admin.route("/admin/users")
        def users():
            """
            @app.route(route="doc")
            """

        @app.route(route="items",  # don't change
                   methods=["GET"])
        def items(req):
            pass
        PY
    end

    it "returns nothing without a FunctionApp" do
      triggers("app.py", %(@app.route(route="x")\ndef x(req):\n    pass\n)).should be_empty
    end
  end

  describe "Node v4" do
    it "reads app.http options and applies the GET/POST default" do
      triggers("src/functions/a.ts", <<-TS).should eq [
        import { app } from "@azure/functions";
        app.http("getItem", {
            methods: ["GET"],
            authLevel: "function",
            route: "items/{id}",
            handler: async () => ({ body: "x" }),
        });
        app.http('hello', { handler });
        // app.http('legacy', { handler });
        TS
        {"getItem", "items/{id}", ["GET"], "function", 2},
        {"hello", nil, ["GET", "POST"], nil, 8},
      ]
    end

    it "maps method shortcuts and durable app.client.http" do
      triggers("a.js", <<-JS).should eq [
        const { app } = require('@azure/functions');
        const df = require('durable-functions');
        app.get('health', async () => ({}));
        app.deleteRequest('remove', { route: 'items/{id}', handler });
        df.app.client.http('start', { route: 'orchestrators/{name}', handler });
        JS
        {"health", nil, ["GET"], nil, 3},
        {"remove", "items/{id}", ["DELETE"], nil, 4},
        {"start", "orchestrators/{name}", ["GET", "POST"], nil, 5},
      ]
    end

    it "skips an unresolvable route and reads non-literal methods as any verb" do
      triggers("a.js", <<-JS).should eq [{"b", nil, [] of String, nil, 3}]
        const { app } = require('@azure/functions');
        app.http('a', { route: ROUTE, handler });
        app.http('b', { methods: ALL_METHODS, handler });
        app.http('c', options);
        app.http('d', { route: `${BASE}/d`, handler });
        JS
    end

    it "reads options through a satisfies clause" do
      triggers("a.ts", <<-TS).should eq [{"fn", "x", ["DELETE"], nil, 2}]
        import { app, HttpFunctionOptions } from "@azure/functions";
        app.http("fn", { route: "x", methods: ["DELETE"], handler } satisfies HttpFunctionOptions);
        TS
    end

    it "ignores an Express app in a file that only imports Azure types" do
      triggers("a.ts", <<-TS).should be_empty
        import { Context } from "@azure/functions";
        const app = express();
        app.get("/api/users", h);
        const db = req.app.get("db");
        TS
    end
  end

  describe ".code_first?" do
    it "requires the language's marker" do
      Noir::AzureFunctionsExtractor.code_first?("a.js", "app.get('/x', h)").should be_false
      Noir::AzureFunctionsExtractor.code_first?("a.js", "const { app } = require('@azure/functions');\napp.http('x', {})").should be_true
      Noir::AzureFunctionsExtractor.code_first?("a.py", "@app.route('/x')").should be_false
      Noir::AzureFunctionsExtractor.code_first?("a.py", "import azure.functions as func\n@app.route(route='x')").should be_true
      Noir::AzureFunctionsExtractor.code_first?("a.cs", "var t = new HttpTrigger();").should be_false
      Noir::AzureFunctionsExtractor.code_first?("a.cs", "Run([HttpTrigger(AuthorizationLevel.Anonymous)] HttpRequestData r)").should be_true
      Noir::AzureFunctionsExtractor.code_first?("a.rb", "[HttpTrigger(]").should be_false
    end
  end
end
