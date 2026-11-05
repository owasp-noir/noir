require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/nextjs"

private def scan_pages(files : Hash(String, String)) : Array(Endpoint)
  temp_dir = File.tempname("noir_nextjs_verb_scope")
  locator = CodeLocator.instance
  locator.clear_all
  files.each do |name, source|
    file = File.join(temp_dir, "pages", "api", name)
    Dir.mkdir_p(File.dirname(file))
    File.write(file, source)
    locator.register_file(file, source)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  Analyzer::Javascript::Nextjs.new(options).analyze
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

private def params_of(endpoints : Array(Endpoint), method : String) : Array(String)
  endpoints.find!(&.method.==(method)).params.map { |p| "#{p.param_type}:#{p.name}" }.sort!
end

describe "Next.js Pages Router verb-branch scoping" do
  it "ignores a verb head spelled inside a string" do
    endpoints = scan_pages({"look.ts" => <<-JS})
      export default async function handler(req, res) {
        const hint = 'if (req.method === "GET") {'
        if (req.method === "POST") {
          return res.json(req.body.p)
        }
        return res.json({ hint, q: req.query.q })
      }
      JS
    params_of(endpoints, "POST").should eq(["body:p", "query:q"])
    params_of(endpoints, "GET").should eq(["query:q"])
  end

  it "does not read a helper's method parameter as the request method" do
    endpoints = scan_pages({"helper.ts" => <<-JS})
      function call(method, req) {
        if (method === "GET") {
          return req.query.helperq
        }
      }
      export default async function handler(req, res) {
        const { method } = req
        if (method === "POST") {
          return res.json(call("GET", req))
        }
        if (method === "GET") {
          return res.json(req.query.listq)
        }
      }
      JS
    params_of(endpoints, "POST").should eq(["query:helperq"])
    params_of(endpoints, "GET").should eq(["query:helperq", "query:listq"])
  end

  # Comments are blanked before this pass, so the non-ASCII text sits in
  # strings, where it survives into the content the heads are matched on.
  it "stays linear on a non-ASCII handler with many verb heads" do
    build = ->(n : Int32) do
      String.build do |io|
        io << "export default async function handler(req, res) {\n  const { method } = req\n"
        n.times do |i|
          io << %(  if (method === "#{%w[GET POST PUT DELETE][i % 4]}") { const x = req.query.q#{i} + "한" }\n)
        end
        io << "}\n"
      end
    end
    small = Time.measure { scan_pages({"big.ts" => build.call(500)}) }
    endpoints = [] of Endpoint
    large = Time.measure { endpoints = scan_pages({"big.ts" => build.call(4000)}) }

    params_of(endpoints, "GET").size.should eq(1000)
    large.should be < small * 16 + 1.second
  end
end
