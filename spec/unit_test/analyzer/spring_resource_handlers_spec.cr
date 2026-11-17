require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"
require "../../../src/analyzer/analyzers/java/spring"

private alias JavaEngine = Analyzer::Java::JavaEngine

# `pattern -> location,location` of each registration in `source`.
private def handlers(source : String, constants = {} of String => String) : Array(String)
  JavaEngine.spring_resource_handlers(JavaEngine.strip_comments(source), constants).map do |handler|
    "#{handler.pattern} -> #{handler.locations.join(",")}"
  end
end

private def replaced?(source : String) : Bool
  JavaEngine.spring_web_auto_config_replaced?(JavaEngine.strip_comments(source))
end

describe "Analyzer::Java::JavaEngine.spring_resource_handlers" do
  it "pairs every pattern with every chained location" do
    handlers(%(registry.addResourceHandler("/a/**", "/b/**").addResourceLocations("classpath:/x/", "file:/y/");))
      .should eq(["/a/** -> classpath:/x/,file:/y/", "/b/** -> classpath:/x/,file:/y/"])
  end

  it "follows the chain across lines, other calls and repeated addResourceLocations" do
    handlers(<<-KOTLIN).should eq(["/** -> classpath:/x/,classpath:/y/"])
      registry
          .addResourceHandler("/**")
          .setCachePeriod(3600)
          .addResourceLocations("classpath:/x/")
          .resourceChain(true)
          .addResourceLocations("classpath:/y/")
      KOTLIN
  end

  it "keeps the locations of one registration out of the next" do
    handlers(<<-JAVA).should eq(["/a/** -> classpath:/x/", "/b/** -> classpath:/y/"])
      registry.addResourceHandler("/a/**").addResourceLocations("classpath:/x/");
      registry.addResourceHandler("/b/**").addResourceLocations("classpath:/y/");
      JAVA
  end

  it "reads constants of the file" do
    handlers(<<-JAVA).should eq(["/a/** -> classpath:/x/"])
      class C {
        private static final String PATTERN = "/a/**";
        static final String LOCATION = "classpath:/x/";
        void add(ResourceHandlerRegistry registry) { registry.addResourceHandler(PATTERN).addResourceLocations(C.LOCATION); }
      }
      JAVA
    handlers(%(const val PATTERN = "/a/**"\nfun add(r: ResourceHandlerRegistry) { r.addResourceHandler(PATTERN).addResourceLocations("classpath:/x/") }))
      .should eq(["/a/** -> classpath:/x/"])
  end

  it "reads the project's qualified constants and + concatenations" do
    handlers(%(registry.addResourceHandler(Paths.ASSETS + "/**").addResourceLocations(Paths.LOCATION);),
      {"Paths.ASSETS" => "/assets", "Paths.LOCATION" => "classpath:/x/"}).should eq(["/assets/** -> classpath:/x/"])
  end

  it "does not take the first literal of a concatenated constant for its value" do
    handlers(<<-JAVA).should eq(["/v/** -> "])
      class C {
        static final String LOCATION = "classpath:/x/" + VERSION + "/";
        void add(ResourceHandlerRegistry registry) { registry.addResourceHandler("/v/**").addResourceLocations(LOCATION); }
      }
      JAVA
  end

  it "drops a Kotlin template, also behind a constant" do
    handlers(<<-KOTLIN).should be_empty
      const val PREFIX = "/assets"
      const val PATTERN = "$PREFIX/**"
      fun add(r: ResourceHandlerRegistry) { r.addResourceHandler(PATTERN).addResourceLocations("classpath:/x/") }
      KOTLIN
  end

  it "ignores a registration quoted in a text block" do
    handlers(%(String template = """\n  registry.addResourceHandler("/a/**").addResourceLocations("classpath:/x/");\n""";)).should be_empty
  end

  it "drops a value it cannot read" do
    handlers(%(registry.addResourceHandler("/**").addResourceLocations("classpath:/x/", "classpath:$dir", Paths.OTHER, root + "/y/")))
      .should eq(["/** -> classpath:/x/"])
    handlers(%(registry.addResourceHandler(PATTERNS).addResourceLocations("classpath:/x/");)).should be_empty
  end

  it "ignores a commented-out registration and a registration without locations" do
    handlers(%(// registry.addResourceHandler("/a/**").addResourceLocations("classpath:/x/");)).should be_empty
    handlers(%(registry.addResourceHandler("/a/**");)).should eq(["/a/** -> "])
  end
end

describe "Analyzer::Java::JavaEngine.spring_web_auto_config_replaced?" do
  it "is true for @EnableWebMvc / @EnableWebFlux and for the configuration classes they import" do
    [
      "@Configuration @EnableWebMvc public class C implements WebMvcConfigurer {}",
      "@org.springframework.web.servlet.config.annotation.EnableWebMvc\nclass C {}",
      "@EnableWebFlux class C : WebFluxConfigurer",
      "public class C extends WebMvcConfigurationSupport {}",
      "public class C extends org.springframework.web.servlet.config.annotation.DelegatingWebMvcConfiguration {}",
      "class C(private val x: X) : WebMvcConfigurationSupport() {}",
      "class C : Marker, WebFluxConfigurationSupport()",
    ].each { |source| replaced?(source).should be_true, source }
  end

  it "is false for a plain configurer, a comment, a string and a type reference" do
    [
      "@Configuration public class C implements WebMvcConfigurer {}",
      "// @EnableWebMvc\n@Configuration class C {}",
      "/* extends WebMvcConfigurationSupport */ class C {}",
      %(class C { String hint = "add @EnableWebMvc to opt out"; }),
      %(class C { String template = """\n@Configuration\n@EnableWebMvc\npublic class WebConfig {}\n"""; }),
      "@ConditionalOnMissingBean(WebMvcConfigurationSupport.class) class C {}",
      "@ConditionalOnMissingBean(value = [Other::class, WebMvcConfigurationSupport::class]) class C",
      "@EnableWebMvcMetrics class C {}",
    ].each { |source| replaced?(source).should be_false, source }
  end
end

describe "Analyzer::Java::JavaEngine.spring_resource_prefix" do
  it "is the directory a /** pattern serves under" do
    JavaEngine.spring_resource_prefix("/**").should eq("")
    JavaEngine.spring_resource_prefix("/assets/**").should eq("/assets")
    JavaEngine.spring_resource_prefix("/a/b/**").should eq("/a/b")
  end

  it "is nil for a pattern that does not map a directory tree" do
    ["/robots.txt", "/img/*", "/{tenant}/**", "/a/*/b/**", "/**/*.js"].each do |pattern|
      JavaEngine.spring_resource_prefix(pattern).should be_nil, pattern
    end
  end
end
