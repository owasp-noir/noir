require "../../func_spec.cr"
require "file_utils"

# A `Route.` call chain deeper than the fiber stack resolves without
# recursion; past `MountPrefixes::MAX_DEPTH` nested mounts a function keeps
# its own URL instead of an ever longer one.
private def ktor_chain_urls(depth : Int32) : Array(String)
  dir = File.tempname("ktor_chain")
  Dir.mkdir_p("#{dir}/src/main/kotlin")
  File.write("#{dir}/build.gradle.kts", %(plugins { id("io.ktor.plugin") version "2.3.0" }\n))
  lines = ["package app", "import io.ktor.server.routing.*",
           %(fun Application.m() { routing { route("/top") { f0() } } })]
  (0...depth - 1).each { |i| lines << %(fun Route.f#{i}() { route("/s#{i}") { f#{i + 1}() } }) }
  lines << %(fun Route.f#{depth - 1}() { get("/leaf") { call.respondText("x") } })
  File.write("#{dir}/src/main/kotlin/R.kt", lines.join("\n"))

  CodeLocator.instance.clear_all
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  options["nolog"] = YAML::Any.new(true)
  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints.map(&.url)
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "Ktor deep mount chains", tags: "functional" do
  it "composes a chain within the cap" do
    ktor_chain_urls(50).should eq(["/top/" + (0...49).map { |i| "s#{i}" }.join('/') + "/leaf"])
  end

  it "keeps the leaf's own URL past the cap, without overflowing" do
    ktor_chain_urls(Analyzer::Kotlin::Ktor::MountPrefixes::MAX_DEPTH + 500).should eq(["/leaf"])
  end
end
