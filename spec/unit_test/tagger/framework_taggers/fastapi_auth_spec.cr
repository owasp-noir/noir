require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "FastAPIAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/python/fastapi_auth", __DIR__)
  main_path = "#{fixture_base}/main.py"

  # main.py line reference:
  # 18: @app.get("/public")
  # 19: async def public_page():
  # 23: @app.get("/profile")
  # 24: async def profile(current_user: User = Depends(get_current_user)):
  # 28: @app.get("/admin")
  # 29: async def admin(token: str = Security(oauth2_scheme)):
  # 33: @app.get("/open")
  # 34: async def open_page():

  it "detects Depends(get_current_user)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 24))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("fastapi_auth")
    endpoint.tags[0].description.should contain("get_current_user")
  end

  it "detects Security(oauth2_scheme)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 29))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/admin", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("oauth2_scheme")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 19))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  # 48: @app.delete("/users/{user_id}", dependencies=[Depends(get_current_active_superuser)])
  # 53: @app.put("/items/{item_id}")   body: owner_id != current_user.id -> 403
  # 61: @app.patch("/notes/{note_id}") Depends(get_current_user) only
  it "tags authorization from a role-checking dependency or the handler's own 403" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    at = ->(line : Int32, method : String) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(main_path, line))) }
    superuser, ownership, plain = at.call(48, "DELETE"), at.call(53, "PUT"), at.call(61, "PATCH")

    # The dependency index is built from the files the detector registered.
    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(main_path)
    begin
      FastAPIAuthTagger.new(noir_options).perform([superuser, ownership, plain])
    ensure
      CodeLocator.instance.clear_all
    end

    superuser.tags.map { |t| {t.name, t.description} }.should eq([
      {"auth", "Protected by FastAPI Depends(get_current_active_superuser)"},
      {"authz", "Protected by FastAPI Depends(get_current_active_superuser)"},
    ])
    ownership.tags.map { |t| {t.name, t.description} }.should eq([
      {"auth", "Protected by FastAPI Depends(get_current_user)"},
      {"authz", "Protected by FastAPI handler ownership/role check"},
    ])
    plain.tags.map(&.name).should eq(["auth"])
  end

  # A handler-body refusal guards the route only when it refuses an
  # anonymous caller.
  # 73: @app.post("/signup")           403 when a setting is off
  # 80: @app.get("/config")            role read, nothing refused
  # 87: @app.delete("/drafts/{id}")    401 when the optional user is None
  # 94: @app.post("/posts/{id}/pin")   403 skipped when the user is None
  it "judges a handler-body check by whether it refuses an anonymous caller" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    at = ->(line : Int32, method : String) { Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(main_path, line))) }
    signup, config, draft, pin = at.call(73, "POST"), at.call(80, "GET"), at.call(87, "DELETE"), at.call(94, "POST")

    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(main_path)
    begin
      FastAPIAuthTagger.new(noir_options).perform([signup, config, draft, pin])
    ensure
      CodeLocator.instance.clear_all
    end

    signup.tags.should be_empty
    config.tags.should be_empty
    draft.tags.map { |t| {t.name, t.description} }.should eq([{"auth", "Protected by FastAPI handler 401 check"}])
    pin.tags.should be_empty
  end

  # body_checks.py: the caller read bare, compared, passed to a helper or
  # closed by an `else`; a non-caller `doc and` prefix; strings holding
  # brackets; a status set on the response. A settings or form
  # dependency is not the caller, and a `for`'s `else` is no check's.
  # Then a class view's `self.user` and a dependency factory.
  it "reads handler-body checks on the caller in their usual shapes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    body = "#{fixture_base}/body_checks.py"
    lines = {6 => "GET", 14 => "GET", 21 => "GET", 29 => "GET", 40 => "GET", 48 => "GET", 56 => "POST", 63 => "POST", 70 => "GET", 90 => "GET", 115 => "POST"}
    endpoints = lines.map { |line, method| Endpoint.new("/#{line}", method, [] of Param, Details.new(PathInfo.new(body, line))) }

    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(body)
    begin
      endpoints = FastAPIAuthTagger.new(noir_options).perform(endpoints)
    ensure
      CodeLocator.instance.clear_all
    end

    verdicts = endpoints.map { |ep| {ep.url, ep.tags.map(&.description)} }.to_h
    verdicts["/6"].should eq(["Protected by FastAPI handler 403 check"])
    verdicts["/14"].should eq(["Protected by FastAPI handler 403 check"])
    verdicts["/21"].should eq(["Protected by FastAPI handler ownership/role check"])
    verdicts["/29"].should eq(["Protected by FastAPI handler ownership/role check"])
    verdicts["/40"].should eq(["Protected by FastAPI handler 403 check"])
    verdicts["/48"].should eq(["Protected by FastAPI handler ownership/role check"])
    verdicts["/56"].should be_empty
    verdicts["/63"].should be_empty
    verdicts["/70"].should be_empty
    # A class-based view's injected caller, read as `self.user`.
    verdicts["/90"].should eq(["Protected by FastAPI Depends(get_current_user)", "Protected by FastAPI handler 403 check"])
    # A router built in a factory function, guarded by a dependency
    # factory whose argument can switch the check off.
    verdicts["/115"].should eq(["Protected by FastAPI create_token_dependency(...) (a setting can make it public)"])
  end

  # app/accounts.py imports `load_account` from loose_deps (checks nothing)
  # and strict_deps (checks `is_admin`), which both define that name.
  #  9: @router.get("/")                Depends(load_account)
  # 14: @router.delete("/{account_id}") Depends(strict_deps.load_account)
  it "judges a dependency by the module the route imports it from" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    accounts = "#{fixture_base}/app/accounts.py"
    loose = Endpoint.new("/accounts/", "GET", [] of Param, Details.new(PathInfo.new(accounts, 9)))
    strict = Endpoint.new("/accounts/{account_id}", "DELETE", [] of Param, Details.new(PathInfo.new(accounts, 14)))

    CodeLocator.instance.clear_all
    Dir.glob("#{fixture_base}/**/*.py").each { |path| CodeLocator.instance.register_path(path) }
    begin
      FastAPIAuthTagger.new(noir_options).perform([loose, strict])
    ensure
      CodeLocator.instance.clear_all
    end

    loose.tags.should be_empty
    strict.tags.map { |t| {t.name, t.description} }.should eq([
      {"authz", "Protected by FastAPI Depends(strict_deps.load_account)"},
    ])
  end

  it "judges dependencies by definition across router subclasses and class-based views" do
    base = File.expand_path("../../../functional_test/fixtures/python/fastapi_auth_cbv", __DIR__)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    routes = "#{base}/app/routes.py"
    optional, me, delete_one, get_public = [14, 19, 26, 33].map do |line|
      Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(routes, line)))
    end

    CodeLocator.instance.clear_all
    Dir.glob("#{base}/**/*.py").each { |path| CodeLocator.instance.register_path(path) }
    begin
      FastAPIAuthTagger.new(noir_options).perform([optional, me, delete_one, get_public])
    ensure
      CodeLocator.instance.clear_all
    end

    # `try_get_current_user` swallows the refusal and returns None.
    optional.tags.map(&.name).should eq(["anonymous"])
    # `UserAPIRouter.__init__` pins `dependencies=[Depends(get_current_user)]`,
    # which raises a module-level 401 exception.
    me.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_user)"])
    # Inherited `user = Depends(get_current_user)` class attribute, base
    # class re-exported through `from .controllers import *`.
    delete_one.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_user)"])
    # `load_group` 404s: a data gate, not a guard.
    get_public.tags.should be_empty
  end

  it "reads Annotated auth aliases, wrapped signatures and router dependencies" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("fastapi_aliases")
    Dir.mkdir_p(tmpdir)
    deps = File.join(tmpdir, "deps.py")
    users = File.join(tmpdir, "users.py")
    admin = File.join(tmpdir, "admin.py")
    File.write(deps, <<-PY)
      SessionDep = Annotated[Session, Depends(get_db)]
      CurrentUser = Annotated[User, Depends(get_current_user)]
      PY
    File.write(users, <<-PY)
      router = APIRouter(prefix="/users")

      @router.get(
          "/",
          dependencies=[Depends(get_current_active_superuser)],
      )
      def read_users(session: SessionDep):
          return []

      @router.patch("/me/password")
      def update_password_me(
          *, session: SessionDep, body: dict, current_user: CurrentUser
      ):
          return None

      @router.post("/signup")
      def register_user(session: SessionDep, email: str):
          return None
      PY
    File.write(admin, <<-PY)
      router = APIRouter(
          prefix="/admin",
          dependencies=[Depends(get_current_active_superuser)],
      )

      @router.get("/metrics")
      def metrics():
          return {}
      PY
    [deps, users, admin].each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(path : String, line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(path, line))) }
      read_users = at.call(users, 3)
      password = at.call(users, 10)
      signup = at.call(users, 16)
      metrics = at.call(admin, 6)

      FastAPIAuthTagger.new(noir_options).perform([read_users, password, signup, metrics])

      read_users.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_active_superuser)"])
      password.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_user) (CurrentUser)"])
      signup.tags.should be_empty
      metrics.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_active_superuser)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "needs the auth word as a whole name component, not a substring" do
    tmpdir = File.tempname("fastapi_callable_words")
    Dir.mkdir_p(tmpdir)
    main = File.join(tmpdir, "main.py")
    File.write(main, <<-PY)
      @app.get("/a")
      def a(author=Depends(get_author_by_id)):
          pass
      @app.get("/b")
      def b(n=Depends(get_token_count)):
          pass
      @app.get("/c")
      def c(repo=Depends(get_roles_repo)):
          pass
      @app.get("/d")
      def d(svc=Depends(permission_service)):
          pass
      @app.get("/e")
      def e(svc=Depends(author_service)):
          pass
      @app.get("/f")
      def f(key=Security(verify_api_key)):
          pass
      @app.get("/g")
      def g(tok=Depends(reusable_oauth2)):
          pass
      @app.get("/h")
      def h(u=Depends(deps.get_current_active_superuser)):
          pass
      @app.get("/i")
      def i(p=Depends(check_permissions)):
          pass
      @app.get("/j")
      def j(u=Depends(require_authenticated_user)):
          pass
      PY

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      endpoints = (0...10).map { |i| Endpoint.new("/#{i}", "GET", [] of Param, Details.new(PathInfo.new(main, i * 3 + 1))) }

      FastAPIAuthTagger.new(noir_options).perform(endpoints)

      endpoints.map(&.tags.empty?).should eq([true, true, true, true, true, false, false, false, false, false])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "ends a handler's signature at a trailing comment or a one-line def" do
    tmpdir = File.tempname("fastapi_header_end")
    Dir.mkdir_p(tmpdir)
    main = File.join(tmpdir, "main.py")
    File.write(main, <<-PY)
      @app.get("/public")
      async def public_items():  # no auth needed (yet)
          return {"items": []}

      @app.get("/ping")
      def ping(): return "pong"

      @app.get("/me")
      async def me(user: User = Depends(get_current_user)):
          return user
      PY

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      public_items, ping, me = [1, 5, 8].map { |line| Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(main, line))) }

      FastAPIAuthTagger.new(noir_options).perform([public_items, ping, me])

      public_items.tags.should be_empty
      ping.tags.should be_empty
      me.tags.map(&.description).should eq(["Protected by FastAPI Depends(get_current_user)"])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
