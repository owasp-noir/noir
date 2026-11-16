require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/java/spark"

private class SparkReadFailureProbe < Analyzer::Java::Spark
  def read_file_content(path : String) : String
    raise ArgumentError.new("synthetic Spark read failure") if File.basename(path) == "poison.java"
    super
  end
end

describe "Spark source scan" do
  after_each do
    CodeLocator.instance.clear_all
    Noir::SkippedFiles.clear
  end

  it "extracts real static configuration with accurate lines and stable method order" do
    source = <<-JAVA
      import static spark.Spark.*;
      class App {
        void setup() {
          String docs = "staticFiles.location('/fake')";
          String text = """
            externalStaticFileLocation("/fake-text-block");
            """;
          // staticFileLocation("/comment");
          // 설정 주석
          spark.Spark.externalStaticFileLocation("/external");
          Spark.staticFileLocation("/legacy");
          staticFiles.externalLocation("/public-external");
          Spark.staticFiles /* live */ .location("/public");
          db.location("/unrelated");
          get("/real", (req, res) -> "ok");
        }
      }
      JAVA
    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, Analyzer::Java::Spark::CONFIG)
    routes.map(&.path).should eq(["/real", "/**", "/**", "/**", "/**"])
    routes[1..].map(&.line).should eq([
      source.lines.index!(&.includes?("/* live */")),
      source.lines.index!(&.includes?("public-external")),
      source.lines.index!(&.includes?("Spark.staticFileLocation(")),
      source.lines.index!(&.includes?("spark.Spark.externalStaticFileLocation(")),
    ])
  end

  it "keeps named and factory-created Spark Service static setters" do
    source = <<-JAVA
      import spark.Service;
      class App {
        void setup() {
          Service http = Service.ignite();
          http.staticFiles.location("/public");
          Service.ignite().staticFiles.externalLocation("/external");
          http.staticFileLocation("/legacy");
          Service.ignite().externalStaticFileLocation("/legacy-external");
        }
      }
      JAVA
    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, Analyzer::Java::Spark::CONFIG)
    routes.map(&.path).should eq(["/**", "/**", "/**", "/**"])
  end

  it "keeps healthy files in order when another file fails" do
    root = File.tempname("noir-spark-isolation")
    Dir.mkdir_p(root)
    locator = CodeLocator.instance
    locator.clear_all
    Noir::SkippedFiles.clear
    %w[first poison last].each do |name|
      path = File.join(root, "#{name}.java")
      File.write(path, "import static spark.Spark.*; class App { void setup() { get(\"/#{name}\", (req, res) -> \"ok\"); } }")
      locator.register_path(path)
    end
    locator.build_extension_index
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])
    options["concurrency"] = YAML::Any.new("1")

    SparkReadFailureProbe.new(options).analyze.map(&.url).should eq(["/first", "/last"])
    failures = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis)
    failures.size.should eq(1)
    failures[0].tech.should eq("java_spark")
    failures[0].message.should contain("synthetic Spark read failure")
  ensure
    FileUtils.rm_rf(root) if root
  end
end
