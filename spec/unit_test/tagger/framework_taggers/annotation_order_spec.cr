require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# An endpoint's line is its route marker, and auth markers are as often
# stacked below it as above it. The taggers used to walk only upward, so
# `@GetMapping` then `@PreAuthorize` came out unauthenticated.
private def tag_route(tagger_class, file : String, source : String, line : Int32, tech : String) : Array(String)
  tmpdir = File.tempname("annotation_order")
  Dir.mkdir_p(tmpdir)
  path = File.join(tmpdir, file)
  File.write(path, source)

  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(path, line))
  details.technology = tech
  endpoint = Endpoint.new("/x", "GET", [] of Param, details)
  tagger_class.new(options).perform([endpoint])
  endpoint.tags.map(&.name)
ensure
  FileUtils.rm_rf(tmpdir) if tmpdir
end

describe "auth markers below the route marker" do
  it "Spring: @PreAuthorize below a multi-line @GetMapping" do
    source = <<-JAVA
      @RestController
      public class C {
          @GetMapping(
              value = "/x")
          @PreAuthorize("hasRole('ADMIN')")
          public String x() { return "x"; }
      }
      JAVA
    tag_route(SpringAuthTagger, "C.java", source, 3, "java_spring").should contain("auth")
  end

  it "Spring: does not read the next handler's annotations" do
    source = <<-JAVA
      @RestController
      public class C {
          @GetMapping("/open")
          public String open() { return "x"; }

          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/x")
          public String x() { return "x"; }
      }
      JAVA
    tag_route(SpringAuthTagger, "C.java", source, 3, "java_spring").should_not contain("auth")
  end

  it "NestJS: @UseGuards below @Get" do
    source = <<-TS
      @Controller('c')
      export class C {
        @Get('x')
        @UseGuards(AuthGuard('jwt'))
        x() { return 1; }
      }
      TS
    tag_route(NestjsAuthTagger, "c.controller.ts", source, 3, "js_nestjs").should contain("auth")
  end

  it "NestJS: @Public below @Get outranks a class guard" do
    source = <<-TS
      @UseGuards(AuthGuard('jwt'))
      @Controller('c')
      export class C {
        @Get('x')
        @Public()
        x() { return 1; }
      }
      TS
    tag_route(NestjsAuthTagger, "c.controller.ts", source, 4, "js_nestjs").should_not contain("auth")
  end

  it "Symfony: #[IsGranted] below #[Route]" do
    source = <<-PHP
      <?php
      class A {
          #[Route('/x')]
          #[IsGranted('ROLE_ADMIN')]
          public function x() {}
      }
      PHP
    tag_route(PhpAuthTagger, "A.php", source, 3, "php_symfony").should contain("auth")
  end

  it "Sanic: @protected() below @app.route" do
    source = <<-PY
      app = Sanic("x")

      @app.route("/x")
      @protected()
      async def x(request):
          return text("x")
      PY
    tag_route(PythonMiscAuthTagger, "app.py", source, 3, "python_sanic").should contain("auth")
  end

  it "Rust: a guard attribute below the route attribute" do
    source = <<-RS
      #[get("/x")]
      #[guard = "admin"]
      async fn x() -> HttpResponse { HttpResponse::Ok().finish() }
      RS
    tag_route(RustAuthTagger, "main.rs", source, 1, "rust_actix_web").should contain("auth")
  end
end
