require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` under a temp dir, tags the endpoint whose code path is
# `file` at `line` (and whose handler is `handler`, a name and line in
# `file`), and returns its `flask_auth` tags.
private def flask_tags(files : Hash(String, String), file : String, line : Int32, method : String = "GET",
                       handler : {String, Int32}? = nil) : Array(Tag)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("flask_requires")
  files.each do |name, source|
    path = File.join(tmpdir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(File.join(tmpdir, file), line))
  details.technology = "python_flask"
  endpoint = Endpoint.new("/x", method, [] of Param, details)
  handler.try { |name, def_line| endpoint.handler = Handler.new(name, File.join(tmpdir, file), def_line) }
  FlaskAuthTagger.new(options).perform([endpoint])[0].tags.select(&.tagger.==("flask_auth"))
ensure
  FileUtils.rm_rf(tmpdir) if tmpdir
  CodeLocator.instance.clear_all
end

# Each clause as its atoms; two layers asking the same count once.
private def atoms(tag : Tag) : Array(Array(String))
  (tag.requires || [] of Access::Clause).map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }).uniq!
end

describe "FlaskAuthTagger requires" do
  it "joins every guard stacked on the view, the first naming the tag" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 4)
      from flask_login import login_required
      from flask_security import roles_required

      @app.route('/x')
      @login_required
      @roles_required('admin', 'editor')
      def x():
          return 'x'
      PY
    tags.size.should eq(1)
    tags[0].description.should eq("Protected by flask-login login_required")
    atoms(tags[0]).should eq([["authenticated"], ["role:admin"], ["role:editor"]])
  end

  it "reads a library name only where the file imports it from the library" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 3)
      from acme.auth import login_required

      @app.route('/x')
      @login_required
      def x():
          return 'x'
      PY
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:flask-login login_required"]])
  end

  it "keeps a guest-admitting jwt_required unresolved" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 3)
      from flask_jwt_extended import jwt_required

      @app.route('/x')
      @jwt_required(optional=True)
      def x():
          return 'x'
      PY
    atoms(tags[0]).should eq([["unresolved:jwt_required(optional=True)"]])
  end

  it "keeps a project decorator's arguments as text, signed in by its verdict" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 11)
      from flask import abort
      from flask_login import current_user

      def role_required(role):
          def wrap(f):
              if not current_user.is_authenticated:
                  abort(401)
              return f
          return wrap

      @app.route('/x')
      @role_required('admin')
      def x():
          return 'x'
      PY
    tags[0].description.should eq("Protected by role_required")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:role_required('admin')"]])
  end

  it "reads a class list entry as written, not by its name alone" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 11, handler: {"Items.get", 8})
      from flask_jwt_extended import jwt_required
      from flask_login import login_required

      class Items(Resource):
          method_decorators = [login_required, jwt_required(optional=True)]

          # the verb
          def get(self):
              return {}

      api.add_resource(Items, "/items")
      PY
    tags[0].description.should eq("Protected by flask-login login_required")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:jwt_required(optional=True)"]])
  end

  it "reads Flask-HTTPAuth roles only on an object it builds" do
    source = <<-PY
      from flask_httpauth import HTTPBasicAuth

      auth = HTTPBasicAuth()
      token_auth = make_auth()

      @app.route('/x')
      @auth.login_required(role=['admin', 'ops'])
      def x():
          return 'x'

      @app.route('/y')
      @token_auth.login_required(role='admin')
      def y():
          return 'y'
      PY
    atoms(flask_tags({"app.py" => source}, "app.py", 6)[0]).should eq([["role:admin", "role:ops"]])
    atoms(flask_tags({"app.py" => source}, "app.py", 11)[0]).should eq([["authenticated"], ["unresolved:flask-httpauth token_auth"]])
  end

  it "adds every before_request hook of the router to the view's own guard" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 14)
      from flask import abort
      from flask_login import current_user, login_required

      @bp.before_request
      def require_login():
          if not current_user.is_authenticated:
              abort(401)

      @bp.before_request
      def require_admin():
          if request.path.startswith('/admin') and not current_user.is_admin:
              abort(403)

      @bp.route('/x')
      @login_required
      def x():
          return 'x'
      PY
    tags[0].description.should eq("Protected by flask-login login_required")
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:bp.before_request def require_admin():"]])
  end

  it "reads a before_request refusal as signed in only when it is a plain sign-in check" do
    plain = flask_tags({"app.py" => <<-PY}, "app.py", 6)
      @bp.before_request
      def require_login():
          if not current_user.is_authenticated:
              abort(401)

      @bp.route('/x')
      def x():
          return 'x'
      PY
    atoms(plain[0]).should eq([["authenticated"]])
    mixed = flask_tags({"app.py" => <<-PY}, "app.py", 8)
      @bp.before_request
      def require_login():
          if not current_user.is_authenticated:
              abort(401)
          if not current_user.is_admin:
              abort(403)

      @bp.route('/x')
      def x():
          return 'x'
      PY
    atoms(mixed[0]).should eq([["authenticated"], ["unresolved:bp.before_request refusing a caller who is not logged in"]])
  end

  it "keeps a hook on the app, or on the router in another file, unresolved" do
    files = {
      "app.py" => <<-PY,
        from flask import Flask
        app = Flask(__name__)

        @app.before_request
        def admins_only():
            if not current_user.is_admin:
                abort(403)
        PY
      "bp.py" => <<-PY,
        @bp.before_app_request
        def anyone():
            pass

        @bp.before_request
        @staff_required
        def staff():
            pass
        PY
      "views.py" => <<-PY,
        from flask_login import login_required

        @bp.route('/x')
        @login_required
        def x():
            return 'x'
        PY
    }
    atoms(flask_tags(files, "views.py", 3)[0]).sort.should eq([
      ["authenticated"],
      ["unresolved:app.before_request def admins_only():"],
      ["unresolved:bp.before_request def staff():"],
    ])
  end

  it "adds a project decorator that is not judged a guard but refuses" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 9)
      from flask_login import login_required

      def feature_gate(f):
          def wrapper(*args, **kwargs):
              abort(404)
          return wrapper

      # route
      @app.route('/x')
      @login_required
      @feature_gate
      def x():
          return 'x'
      PY
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:feature_gate"]])
  end

  it "keeps a decorators list on an Api or Namespace in the view's file unresolved" do
    tags = flask_tags({"app.py" => <<-PY}, "app.py", 6)
      from flask_login import login_required

      ns = Namespace("v1",
                     decorators=[admin_only])

      @ns.route('/x')
      @login_required
      def x():
          return 'x'
      PY
    atoms(tags[0]).should eq([["authenticated"], ["unresolved:decorators= on an Api or Namespace in app.py"]])
  end

  it "keeps a flask_login guard liftable where the scan sets LOGIN_DISABLED" do
    tags = flask_tags({"app.py" => <<-PY, "settings.py" => "LOGIN_DISABLED = True\n"}, "app.py", 3)
      from flask_login import login_required

      @app.route('/x')
      @login_required
      def x():
          return 'x'
      PY
    atoms(tags[0]).should eq([["authenticated", "unresolved:LOGIN_DISABLED"]])
  end

  it "names the Flask-AppBuilder permission and leaves the Public role open" do
    tags = flask_tags({"views.py" => <<-PY}, "views.py", 7, handler: {"PageView.listing", 7})
      from flask_appbuilder import BaseView, expose
      from flask_appbuilder.security.decorators import has_access, permission_name

      class PageView(BaseView):
          @has_access
          @permission_name("read")
          def listing(self):
              return "x"
      PY
    description = "flask-appbuilder has_access (a setting can make it public)"
    permission = "flask-appbuilder permission can_read on PageView (method_permission_name or class_permission_name may rename it)"
    atoms(tags[0]).should eq([["authenticated", "unresolved:#{description}"], ["unresolved:#{description}", "unresolved:#{permission}"]])
  end
end
