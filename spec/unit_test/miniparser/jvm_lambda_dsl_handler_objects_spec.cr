require "spec"
require "../../../src/models/logger"
require "../../../src/miniparsers/jvm_lambda_dsl_extractor_ts"

# Unit twin of the java/lambda_dsl_handler_objects fixture: which slash-less
# first arguments the lambda-DSL walker believes next to a handler variable
# or handler object.
describe Noir::TreeSitterJvmLambdaDslExtractor do
  javalin = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {"get" => "GET", "post" => "POST", "put" => "PUT"},
    nest_methods: Set{"path"},
    handler_methods: Set{"addHandler"},
    transparent_methods: Set{"routes", "before"},
  )

  extract = ->(body : String) do
    source = <<-JAVA
      import io.javalin.http.Handler;
      class App {
          void run() {
              Handler getOne = ctx -> ctx.result("x");
              #{body}
          }
      }
      JAVA
    Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, javalin).map { |route| {route.verb, route.path} }.sort!
  end

  it "keeps a slash-less pattern with a {param}, :param or inner slash next to a handler variable or object" do
    extract.call(<<-JAVA).should eq([{"GET", "a/{id}"}, {"GET", "b/c"}, {"POST", ":d"}])
      app.get("a/{id}", getOne);
      app.get("b/c", getOne);
      app.post(":d", new CreateHandler());
      JAVA
  end

  it "keeps any pattern inside a path() or routes() group, and for addHandler" do
    extract.call(<<-JAVA).should eq([{"GET", "g"}, {"GET", "users"}, {"GET", "users/h"}, {"POST", "users/n"}, {"PUT", "r"}])
      path("users", () -> {
          get("h", getOne);
          post("n", new CreateHandler());
          get(getOne);
      });
      app.addHandler(HandlerType.GET, "g", getOne);
      routes(() -> {
          put("r", getOne);
      });
      JAVA
  end

  it "drops collection and config calls with the same verb names" do
    extract.call(<<-JAVA).should be_empty
      sessions.put("k", new Foo());
      sessions.put("handlers", getOne);
      row.get("a/b", String.class);
      row.get("{id}", Integer.class);
      routes(() -> {
          before(ctx -> sessions.put("k", new Foo()));
      });
      JAVA
  end
end
