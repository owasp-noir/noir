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
end
