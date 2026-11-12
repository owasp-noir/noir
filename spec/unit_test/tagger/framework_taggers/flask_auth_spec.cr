require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

private def flask_detect(decorator : String) : Endpoint
  tmpdir = File.tempname("flask_auth_extra")
  Dir.mkdir_p(tmpdir)
  app = File.join(tmpdir, "app.py")
  File.write(app, [
    "@app.route('/secret')",
    decorator,
    "def secret():",
    "    return 'ok'",
  ].join("\n"))

  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(app, 1))
  details.technology = "python_flask"
  endpoint = Endpoint.new("/secret", "GET", [] of Param, details)

  FlaskAuthTagger.new(noir_options).perform([endpoint])
  FileUtils.rm_rf(tmpdir)
  endpoint
end

describe "FlaskAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/python/flask_auth", __DIR__)
  app_path = "#{fixture_base}/app.py"

  # app.py line reference — the route decorator, which is the line the
  # Flask analyzer reports:
  #  8: @app.route('/public')
  # 13: @app.route('/profile')       (@login_required below it)
  # 19: @app.route('/api/data', ...) (multi-line; @jwt_required() below it)
  # 34: @app.route('/misordered')    (@login_required *above* it)

  it "detects @login_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 13))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("flask_auth")
    endpoint.tags[0].description.should contain("login_required")
  end

  it "detects @jwt_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/api/data", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 8))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag a route whose auth decorator sits above the route decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 34))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/misordered", "GET", [] of Param, details)

    FlaskAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "still reads the decorators above a line that is the view itself" do
    tmpdir = File.tempname("flask_auth_def_line")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    File.write(app, "@app.route('/x')\n@login_required\ndef x():\n    return 'ok'\n")

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(app, 3))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)

    FlaskAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)

    endpoint.tags.map(&.name).should eq(["auth"])
  end

  # changedetection.io's `@auth.check_token`: the 403 sits on the wrapped
  # line of a `return make_response(...)`.
  it "reads a credential rejection whose return wraps across lines" do
    tmpdir = File.tempname("flask_auth_wrapped_return")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    File.write(app, <<-PY)
      from functools import wraps
      from flask import request, make_response, jsonify


      def check_token(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('x-api-key') != TOKEN:
                  return make_response(
                      jsonify("Invalid access - API key invalid."), 403
                  )
              return f(*args, **kwargs)
          return decorated


      def check_size(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if len(request.get_data()) > 10:
                  return make_response(
                      jsonify("too big (x-api-key)"), 413
                  )
              return f(*args, **kwargs)
          return decorated


      class Watch(Resource):
          @check_token
          def get(self):
              return {}

          @check_size
          def post(self):
              return {}
      PY

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = {29 => "GET", 33 => "POST"}.map do |line, method|
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new("/watch", method, [] of Param, details)
    end

    FlaskAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.map(&.description).should eq(["Protected by check_token"])
    endpoints[1].tags.should be_empty
  end

  # changedetection.io's real `check_token` only compares the key when
  # `api_access_token_enabled` is set; an escaped quote in a string must
  # not leave a bracket open and join the rest of the body into one line.
  it "says a setting can open a wrapped credential rejection" do
    tmpdir = File.tempname("flask_auth_wrapped_setting")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    File.write(app, <<-PY)
      from functools import wraps
      from flask import request, make_response, jsonify


      def check_token(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if settings.get('api_access_token_enabled'):
                  if request.headers.get('x-api-key') != settings.get('token'):
                      return make_response(
                          jsonify("Invalid access - API key invalid."), 403
                      )
              return f(*args, **kwargs)
          return decorated


      def log_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              log("a \\"( quote", request.headers.get('x-api-key'))
              rv = f(*args, **kwargs)
              if not rv:
                  return rv
              metrics.observe(rv, 404)
              return rv
          return decorated


      class Watch(Resource):
          @check_token
          def get(self):
              return {}

          @log_key
          def post(self):
              return {}
      PY

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = {31 => "GET", 35 => "POST"}.map do |line, method|
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new("/watch", method, [] of Param, details)
    end

    FlaskAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.map(&.description).should eq(["Protected by check_token (a setting can make it public)"])
    endpoints[1].tags.should be_empty
  end

  # Joined lines only feed the credential-mismatch rule, under a condition
  # that does not read the request; a CSRF / cursor comparison or a bare
  # key presence is no caller identity.
  it "keeps look-alike rejections and request comparisons open" do
    tmpdir = File.tempname("flask_auth_wrapped_lookalikes")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    source = <<-PY
      from functools import wraps
      from flask import Flask, request, make_response, jsonify, abort, redirect, url_for

      def rate_limited(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              bucket = request.headers.get('x-api-key') or request.remote_addr
              if limiter.hit(bucket):
                  return make_response(
                      jsonify("Too many requests"), 429
                  )
              return f(*args, **kwargs)
          return decorated

      def documented(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              rv = f(*args, **kwargs)
              return make_response(
                  jsonify(rv, errors="may answer 400, 401"), 200
              )
          return decorated

      def json_only(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              log.info("tok %s", request.headers.get('Authorization'))
              if not request.is_json:
                  return make_response(
                      jsonify(error="expected JSON"), 400
                  )
              return f(*args, **kwargs)
          return decorated

      def key_on_writes(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.method == 'POST':
                  if request.headers.get('x-api-key') != TOKEN:
                      return make_response(
                          jsonify("bad key"), 403
                      )
              return f(*args, **kwargs)
          return decorated

      def login_or_any_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('X-Api-Key'):
                  return f(*args, **kwargs)
              if not current_user.is_authenticated:
                  return redirect(url_for('login'))
              return f(*args, **kwargs)
          return decorated

      def check_token(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('x-api-key') != TOKEN:  # compare (key]
                  return make_response(  # wrapped ( paren
                      jsonify("Invalid [key) ("), 403  # trailing ]
                  )
              return f(*args, **kwargs)
          return decorated

      def transfer():
          if request.headers.get('X-CSRF-Token') != request.cookies.get('csrf_token'):
              abort(403)
          return "ok"

      def items():
          if request.args.get('page_token') != expected_cursor():
              return jsonify(error="stale cursor"), 403
          return "ok"

      class Views:
          @rate_limited
          def limited(self):
              return "ok"

          @documented
          def documented_view(self):
              return "ok"

          @json_only
          def json_view(self):
              return "ok"

          @key_on_writes
          def kw(self):
              return "ok"

          @login_or_any_key
          def report(self):
              return "ok"

          @check_token
          def token_view(self):
              return "ok"

      PY
    File.write(app, source)

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    names = %w[limited documented_view json_view kw report token_view transfer items]
    endpoints = names.map do |name|
      line = source.lines.index!(&.includes?("def #{name}(")) + 1
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new("/#{name}", name.in?("transfer", "json_view") ? "POST" : "GET", [] of Param, details)
    end

    FlaskAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.to_h { |endpoint| {endpoint.url, endpoint.tags.map(&.description)} }.should eq({
      "/limited"         => [] of String,
      "/documented_view" => [] of String,
      "/json_view"       => [] of String,
      "/kw"              => [] of String,
      "/report"          => [] of String,
      "/token_view"      => ["Protected by check_token"],
      "/transfer"        => [] of String,
      "/items"           => [] of String,
    })
  end

  # The mismatch must be the credential's own (`cred and not verify(cred)`
  # lets anonymous through), against a value the caller does not send,
  # with no earlier way to the view that skips it.
  it "reads a credential mismatch only when anonymous cannot get past it" do
    tmpdir = File.tempname("flask_auth_credential_mismatch")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    source = <<-PY
      from functools import wraps
      from flask import request, make_response, jsonify

      def optional_token(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('Authorization') and not verify(request.headers.get('Authorization')):
                  return make_response(
                      jsonify("bad token"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def caller_list(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('x-api-key') not in request.args.getlist('allowed'):
                  return make_response(
                      jsonify("bad key"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def writes_need_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.method == 'GET':
                  return f(*args, **kwargs)
              if request.headers.get('x-api-key') != TOKEN:
                  return make_response(
                      jsonify("bad key"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def json_and_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if not request.is_json:
                  return make_response(
                      jsonify("expected json"), 400
                  )
              elif request.headers.get('x-api-key') != TOKEN:
                  return make_response(
                      jsonify("bad key"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def public_flag_or_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.args.get('public') == '1':
                  pass
              elif request.headers.get('x-api-key') != TOKEN:
                  return make_response(
                      jsonify("bad key"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def local_copy(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              expected = request.args.get('expected_key')
              if request.headers.get('x-api-key') != expected:
                  return make_response(
                      jsonify("bad key"), 403
                  )
              return f(*args, **kwargs)
          return decorated

      def missing_key(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if not request.headers.get('x-api-key'):
                  return make_response(
                      jsonify("key required"), 401
                  )
              return f(*args, **kwargs)
          return decorated

      def missing_key_enum(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if not request.headers.get('x-api-key'):
                  return jsonify("key required"), HTTPStatus.UNAUTHORIZED
              return f(*args, **kwargs)
          return decorated

      def bad_key_enum(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if request.headers.get('x-api-key') != TOKEN:
                  return jsonify("bad key"), HTTPStatus.FORBIDDEN
              return f(*args, **kwargs)
          return decorated

      def anon_abort(f):
          @wraps(f)
          def decorated(*args, **kwargs):
              if not current_user.is_authenticated:
                  abort(status.HTTP_403_FORBIDDEN)
              return f(*args, **kwargs)
          return decorated

      class Views:
          @optional_token
          def optional(self):
              return "ok"

          @caller_list
          def callerlist(self):
              return "ok"

          @writes_need_key
          def writes(self):
              return "ok"

          @json_and_key
          def jsonkey(self):
              return "ok"

          @public_flag_or_key
          def publicflag(self):
              return "ok"

          @local_copy
          def localcopy(self):
              return "ok"

          @missing_key
          def missing(self):
              return "ok"

          @missing_key_enum
          def missingenum(self):
              return "ok"

          @bad_key_enum
          def badkeyenum(self):
              return "ok"

          @anon_abort
          def anonabort(self):
              return "ok"
      PY
    File.write(app, source)

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    names = %w[optional callerlist writes jsonkey publicflag localcopy missing missingenum badkeyenum anonabort]
    endpoints = names.map do |name|
      line = source.lines.index!(&.includes?("def #{name}(")) + 1
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new("/#{name}", name == "jsonkey" ? "POST" : "GET", [] of Param, details)
    end

    FlaskAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.to_h { |endpoint| {endpoint.url, endpoint.tags.map(&.description)} }.should eq({
      "/optional"    => [] of String,
      "/callerlist"  => [] of String,
      "/writes"      => [] of String,
      "/jsonkey"     => ["Protected by json_and_key"],
      "/publicflag"  => [] of String,
      "/localcopy"   => [] of String,
      "/missing"     => ["Protected by missing_key"],
      "/missingenum" => ["Protected by missing_key_enum"],
      "/badkeyenum"  => ["Protected by bad_key_enum"],
      "/anonabort"   => ["Protected by anon_abort"],
    })
  end

  it "detects bare @jwt_required (no parentheses)" do
    endpoint = flask_detect("@jwt_required")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "detects @jwt_required() call form" do
    endpoint = flask_detect("@jwt_required()")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "detects flask-security @auth_required" do
    endpoint = flask_detect("@auth_required('token', 'session')")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("auth_required")
  end

  it "detects flask-security @permission_required" do
    endpoint = flask_detect("@permission_required('admin')")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("permission_required")
  end

  # flask_setup_gated_guard/app.py: the view is reached when the app is
  # not set up (a setting) or when the caller is an admin, in the `and`
  # form and the nested form (#3292). `authed() and not is_admin()` lets
  # an anonymous caller through, so it is no guard.
  it "judges each path past a setup-gated refusal on its own" do
    base = File.expand_path("../../../functional_test/fixtures/python/flask_setup_gated_guard", __DIR__)
    app = "#{base}/app.py"
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    endpoints = {67 => "/setup/git", 73 => "/setup/nested", 79 => "/admin/thing", 85 => "/anyone", 113 => "/posts", 119 => "/scores"}.map do |line, url|
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new(url, "DELETE", [] of Param, details)
    end

    verdicts = FlaskAuthTagger.new(noir_options).perform(endpoints).map { |ep| {ep.url, ep.tags.select(&.name.== "auth").map(&.description)} }.to_h
    verdicts["/setup/git"].should eq(["Protected by managers_only (a setting can make it public)"])
    verdicts["/setup/nested"].should eq(["Protected by nested_managers_only (a setting can make it public)"])
    verdicts["/admin/thing"].should eq(["Protected by admins_only"])
    verdicts["/anyone"].should be_empty
    # A GET gets past `request.method == "POST" and ...`: the caller's choice.
    verdicts["/posts"].should be_empty
    # The `elif` refuses, but the public branch above it is a way in.
    verdicts["/scores"].should eq(["Protected by public_or_members (a setting can make it public)"])
  end
end
