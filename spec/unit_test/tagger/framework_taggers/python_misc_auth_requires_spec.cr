require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` under a temp dir, tags the `technology` endpoint whose
# code path is `file` at `line` (handler at `handler_line`, if given), and
# returns its `python_misc_auth` tags.
private def misc_tags(files : Hash(String, String), file : String, line : Int32, technology : String,
                      handler_line : Int32? = nil, method : String = "GET") : Array(Tag)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("misc_requires")
  files.each do |name, source|
    path = File.join(tmpdir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(File.join(tmpdir, file), line))
  details.technology = technology
  endpoint = Endpoint.new("/x", method, [] of Param, details)
  handler_line.try { |def_line| endpoint.handler = Handler.new("H.get", File.join(tmpdir, file), def_line) }
  PythonMiscAuthTagger.new(options).perform([endpoint])[0].tags.select(&.tagger.==("python_misc_auth"))
ensure
  FileUtils.rm_rf(tmpdir) if tmpdir
  CodeLocator.instance.clear_all
end

# Each clause as its atoms; two layers asking the same count once.
private def atoms(tag : Tag) : Array(Array(String))
  (tag.requires || [] of Access::Clause).map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }).uniq!
end

describe "PythonMiscAuthTagger requires" do
  it "reads Tornado's authenticated where the name is bound to it" do
    source = <<-PY
      import tornado.web
      from tornado.web import authenticated

      class H(tornado.web.RequestHandler):
          @tornado.web.authenticated
          def get(self):
              pass
      PY
    atoms(misc_tags({"app.py" => source}, "app.py", 6, "python_tornado", 6)[0]).should eq([["authenticated"]])
    bare = source.sub("@tornado.web.authenticated", "@authenticated")
    atoms(misc_tags({"app.py" => bare}, "app.py", 6, "python_tornado", 6)[0]).should eq([["authenticated"]])
  end

  it "keeps a bare authenticated the file does not import from Tornado unread" do
    tags = misc_tags({"app.py" => <<-PY}, "app.py", 3, "python_tornado", 3)
      class H(BaseHandler):
          @authenticated
          def get(self):
              pass
      PY
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:Tornado @authenticated"]])
  end

  it "joins sanic-jwt protected and scoped stacked under the route" do
    tags = misc_tags({"app.py" => <<-PY}, "app.py", 3, "python_sanic")
      from sanic_jwt import protected, scoped

      @app.route("/x")
      @protected()
      @scoped(["read", "write"], require_all=False)
      async def x(request):
          pass
      PY
    tags[0].description.should eq("Protected by Sanic @protected decorator")
    atoms(tags[0]).should eq([["authenticated"], ["scope:read", "scope:write"]])
  end

  it "keeps a sanic-jwt guard unread for the OPTIONS request it lets through" do
    tags = misc_tags({"app.py" => <<-PY}, "app.py", 3, "python_sanic", method: "OPTIONS")
      from sanic_jwt import protected

      @app.route("/x", methods=["OPTIONS"])
      @protected()
      async def x(request):
          pass
      PY
    atoms(tags[0]).should eq([["unresolved:protected() (skipped for OPTIONS)"]])
  end
end
