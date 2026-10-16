require "spec"
require "../../../src/models/logger"
require "../../../src/miniparsers/jvm_lambda_dsl_extractor_ts"
require "../../../src/miniparsers/helidon_se_extractor_ts"

# `Map#put`, `ResultSet#get` and `Config#get` share the verb names of the
# routing DSLs. A route path starts with `/` (or `*`); a slash-less first
# argument is believed only next to a lambda or method-reference handler.
describe "collection calls that share route verb names" do
  spark_config = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {"get" => "GET", "put" => "PUT"},
    nest_methods: Set{"path"}
  )

  describe Noir::TreeSitterJvmLambdaDslExtractor do
    it "drops a Map/JDBC/config key whose second argument is not a lambda or method reference" do
      source = <<-JAVA
        import static spark.Spark.*;

        class App {
            void run() {
                templateMap.put("k", new Foo());
                row.get("C", String.class);
                config.get("db.url", String.class);
                Map<String, Object> m = new HashMap<>() {{
                    put("csrf", uuid);
                }};
            }
        }
        JAVA

      Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, spark_config).should be_empty
    end

    it "keeps route-shaped paths and slash-less paths behind a lambda or method reference" do
      source = <<-JAVA
        import static spark.Spark.*;

        class App {
            void run() {
                get("/a", new Handler());
                get("b", (req, res) -> "b");
                get("c", Api::c);
            }
        }
        JAVA

      routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, spark_config)
      routes.map { |route| {route.verb, route.path} }.sort!.should eq([
        {"GET", "/a"}, {"GET", "b"}, {"GET", "c"},
      ])
    end
  end

  describe Noir::TreeSitterHelidonSeExtractor do
    it "drops a Map/JDBC/config key whose second argument is not a lambda or method reference" do
      source = <<-JAVA
        package io.helidon.webserver.observe;

        class Escapes {
            void run() {
                result.put("br", "br");
                row.get("ID", Integer.class);
                config.get("db.url", String.class);
            }
        }
        JAVA

      Noir::TreeSitterHelidonSeExtractor.extract(source).routes.should be_empty
    end

    it "keeps route-shaped paths and slash-less paths behind a lambda or method reference" do
      source = <<-JAVA
        package io.helidon.webserver.observe;

        class Svc {
            void rules(HttpRules rules) {
                rules.get("/a", handler)
                     .get("b", (req, res) -> res.send("b"))
                     .post("c", Svc::c);
            }
        }
        JAVA

      routes = Noir::TreeSitterHelidonSeExtractor.extract(source).routes
      routes.map { |route| {route.verb, route.path} }.sort!.should eq([
        {"GET", "/a"}, {"GET", "b"}, {"POST", "c"},
      ])
    end
  end
end
