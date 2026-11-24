require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` under a temp dir and tags endpoint `url` of the route in
# `main.py` whose decorator names `route` (default: `url`).
private def fastapi_endpoint(files : Hash(String, String), url : String, route : String = url) : Endpoint
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("fastapi_requires")
  Dir.mkdir_p(tmpdir)
  files.each do |name, source|
    path = File.join(tmpdir, name)
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  line = files["main.py"].lines.index!(&.matches?(/^\s*@\s*\w+\.\w+\(\s*"#{Regex.escape(route)}"/)) + 1
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(File.join(tmpdir, "main.py"), line))
  details.technology = "python_fastapi"
  endpoint = Endpoint.new(url, "GET", [] of Param, details)
  FastAPIAuthTagger.new(options).perform([endpoint])
  FileUtils.rm_rf(tmpdir)
  CodeLocator.instance.clear_all
  endpoint
end

# `{name => sorted clause atoms}` of the route's fastapi_auth tags.
private def fastapi_requires(files : Hash(String, String), url : String, route : String = url) : Hash(String, Array(Array(String)))
  fastapi_endpoint(files, url, route).tags.select(&.tagger.==("fastapi_auth")).to_h do |tag|
    {tag.name, (tag.requires || [] of Access::Clause).map(&.any_of.map(&.to_s).sort!).sort!}
  end
end

FASTAPI_REQUIRES_USERS = <<-PY
  from fastapi import Depends, HTTPException, Security
  from fastapi.security import OAuth2PasswordBearer, SecurityScopes

  oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")


  async def get_current_user(security_scopes: SecurityScopes, token: str = Depends(oauth2_scheme)):
      user = decode(token)
      if user is None:
          raise HTTPException(status_code=401)
      for scope in security_scopes.scopes:
          if scope not in user.granted:
              raise HTTPException(status_code=401)
      return user


  async def get_current_active_user(current_user=Security(get_current_user, scopes=["me"])):
      return current_user


  async def get_loose_user(security_scopes: SecurityScopes, token: str = Depends(oauth2_scheme)):
      if not set(security_scopes.scopes) <= decode(token).granted:
          raise HTTPException(status_code=401)
      return token
  PY

describe "FastAPIAuthTagger requires" do
  it "reads the scopes a dependency checks, its parent's added to the route's" do
    main = <<-PY
      from users import get_current_active_user, get_current_user, get_loose_user

      @app.get("/items")
      async def items(user=Security(get_current_active_user, scopes=["items:read", "items:write"])):
          return []

      @app.get("/me")
      async def me(user=Depends(get_current_active_user)):
          return user
      PY
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/items")["auth"]
      .should eq([["authenticated"], ["scope:items:read"], ["scope:items:write"], ["scope:me"]])
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/me")["auth"]
      .should eq([["authenticated"], ["scope:me"]])
  end

  it "keeps scopes no dependency visibly checks as one unresolved clause with their text" do
    main = <<-PY
      from users import get_loose_user

      @app.get("/loose")
      async def loose(user=Security(get_loose_user, scopes=["items:read"])):
          return user
      PY
    requires = fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/loose")["auth"]
    requires.should eq([["authenticated"], ["unresolved"]])
  end

  it "adds a router's scopes to the route's own" do
    main = <<-PY
      from fastapi import APIRouter
      from users import get_current_user

      router = APIRouter(dependencies=[Security(get_current_user, scopes=["admin"])])

      @router.get("/panel")
      async def panel(user=Security(get_current_user, scopes=["panel"])):
          return {}
      PY
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/panel")["auth"]
      .should eq([["authenticated"], ["scope:admin"], ["scope:panel"]])
  end

  it "reads FastAPI's schemes by auto_error, and only FastAPI's" do
    main = <<-PY
      from fastapi import Depends
      from fastapi.security import APIKeyHeader, HTTPBearer
      from vendor import HTTPBasic

      bearer = HTTPBearer()
      soft_bearer = HTTPBearer(auto_error=False)
      api_key = APIKeyHeader(name="X-API-Key")
      basic_auth = HTTPBasic()

      @app.get("/bearer")
      async def with_bearer(creds=Depends(bearer)):
          return {}

      @app.get("/soft")
      async def soft(creds=Depends(soft_bearer)):
          return {}

      @app.get("/key")
      async def key(value: str = Security(api_key)):
          return {}

      @app.get("/vendor")
      async def vendor(creds=Depends(basic_auth)):
          return {}
      PY
    files = {"main.py" => main}
    fastapi_requires(files, "/bearer")["auth"].should eq([["authenticated"]])
    fastapi_requires(files, "/soft")["auth"].should eq([["unresolved"]])
    fastapi_requires(files, "/key")["auth"].should eq([["authenticated"]])
    # A same-named class from another package is not read as FastAPI's.
    fastapi_requires(files, "/vendor")["auth"].should eq([["unresolved"]])
  end

  it "names roles only where the dependency compares the caller's role with a literal it is handed" do
    main = <<-PY
      from fastapi import Depends, HTTPException
      from users import get_current_user

      STAFF = ["staff", "admin"]

      class RoleChecker:
          def __init__(self, allowed_roles):
              self.allowed_roles = allowed_roles

          def __call__(self, user=Depends(get_current_user)):
              if user.role not in self.allowed_roles:
                  raise HTTPException(status_code=403)
              return user

      def require_role(role: str):
          def checker(user=Depends(get_current_user)):
              if user.role != role:
                  raise HTTPException(status_code=403)
              return user
          return checker

      def get_current_active_superuser(current_user=Depends(get_current_user)):
          if not current_user.is_superuser:
              raise HTTPException(status_code=403)
          return current_user

      def staff_only(user=Depends(get_current_user)):
          if user.role not in STAFF:
              raise HTTPException(status_code=403)
          return user

      @app.get("/checker", dependencies=[Depends(RoleChecker(["admin", "editor"]))])
      async def checker():
          return {}

      @app.get("/configured", dependencies=[Depends(RoleChecker(load_roles()))])
      async def configured():
          return {}

      @app.get("/factory")
      async def factory(user=Depends(require_role("admin"))):
          return {}

      @app.get("/super")
      async def superuser(user=Depends(get_current_active_superuser)):
          return {}

      @app.get("/staff")
      async def staff(user=Depends(staff_only)):
          return {}
      PY
    files = {"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}
    fastapi_requires(files, "/checker")["auth"].should eq([["authenticated"], ["role:admin", "role:editor"]])
    fastapi_requires(files, "/configured")["auth"].should eq([["authenticated"], ["unresolved"]])
    fastapi_requires(files, "/factory")["authz"].should eq([["authenticated"], ["role:admin"]])
    # A function name is not a role.
    fastapi_requires(files, "/super")["authz"].should eq([["authenticated"], ["unresolved"]])
    fastapi_requires(files, "/staff")["authz"].should eq([["authenticated"], ["role:admin", "role:staff"]])
  end

  it "keeps a role or field check answered with 401" do
    main = <<-PY
      from fastapi import Depends, HTTPException
      from users import get_current_user

      def admin_only(user=Depends(get_current_user)):
          if user.role != "admin":
              raise HTTPException(status_code=401)
          return user

      def superuser_only(current_user=Depends(get_current_user)):
          if not current_user.is_superuser:
              raise HTTPException(status_code=401)
          return current_user

      @app.get("/admin")
      async def admin(user=Depends(admin_only)):
          return {}

      @app.get("/super")
      async def superuser(user=Depends(superuser_only)):
          return {}
      PY
    files = {"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}
    fastapi_requires(files, "/admin")["authz"].should eq([["authenticated"], ["role:admin"]])
    fastapi_requires(files, "/super")["authz"].should eq([["authenticated"], ["unresolved"]])
  end

  it "names a role only off the injected caller" do
    main = <<-PY
      from fastapi import Depends, HTTPException
      from users import get_current_user

      def require_public_doc(doc=Depends(load_doc), user=Depends(get_current_user)):
          if doc.role != "public":
              raise HTTPException(status_code=403)
          return doc

      @app.get("/docs/{doc_id}")
      async def read_doc(d=Depends(require_public_doc)):
          return d
      PY
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/docs/{doc_id}")["authz"]
      .should eq([["authenticated"], ["unresolved"]])
  end

  it "keeps the condition of a 401 that is not an absence test, and a setting that lifts one" do
    main = <<-PY
      from fastapi import Depends, Header, HTTPException
      from users import get_current_user

      def tenant_user(x_tenant: str = Header(...), user=Depends(get_current_user)):
          if user.tenant_id != x_tenant:
              raise HTTPException(status_code=401)
          return user

      def maybe_user(token: str = Header(None)):
          if settings.AUTH_ENABLED:
              if not token:
                  raise HTTPException(status_code=401)
          return token

      @app.get("/tenant")
      async def tenant(u=Depends(tenant_user)):
          return u

      @app.get("/maybe")
      async def maybe(t=Depends(maybe_user)):
          return t
      PY
    files = {"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}
    fastapi_requires(files, "/tenant")["auth"].should eq([["authenticated"], ["unresolved"]])
    fastapi_requires(files, "/maybe")["auth"].should eq([["authenticated", "unresolved"]])
  end

  it "reads a role constant only when it is bound once and never changed here" do
    main = <<-PY
      import os
      from fastapi import Depends, HTTPException
      from users import get_current_user
      from roles import IMPORTED

      ADMIN_ROLE = "admin"
      ADMIN_ROLE = os.getenv("ADMIN_ROLE", "superadmin")
      EDITORS = ["editor"]
      EDITORS.append("intern")

      def reassigned(user=Depends(get_current_user)):
          if user.role != ADMIN_ROLE:
              raise HTTPException(status_code=403)

      def mutated(user=Depends(get_current_user)):
          if user.role not in EDITORS:
              raise HTTPException(status_code=403)

      def imported(user=Depends(get_current_user)):
          if user.role not in IMPORTED:
              raise HTTPException(status_code=403)

      @app.get("/reassigned")
      async def a(u=Depends(reassigned)):
          return u

      @app.get("/mutated")
      async def b(u=Depends(mutated)):
          return u

      @app.get("/imported")
      async def c(u=Depends(imported)):
          return u
      PY
    files = {"users.py" => FASTAPI_REQUIRES_USERS, "roles.py" => %(IMPORTED = ["admin"]\n), "main.py" => main}
    %w[/reassigned /mutated /imported].each do |url|
      fastapi_requires(files, url)["authz"].should eq([["authenticated"], ["unresolved"]])
    end
  end

  it "keeps a conditional raise of any exception" do
    main = <<-PY
      from fastapi import Depends, HTTPException
      from users import get_current_user

      def acme_admin(user=Depends(get_current_user)):
          if user.org != "acme":
              raise NotOwner()
          if user.role != "admin":
              raise HTTPException(status_code=403)
          return user

      @app.get("/custom")
      async def custom(u=Depends(acme_admin)):
          return u
      PY
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/custom")["authz"]
      .should eq([["authenticated"], ["role:admin"], ["unresolved"]])
  end

  it "does not read a 403 on a setting as a sign-in" do
    main = <<-PY
      from fastapi import Depends, HTTPException

      def require_feature(settings=Depends(get_settings)):
          if not settings.signup_enabled:
              raise HTTPException(status_code=403)

      def require_user(token: str = Header(None)):
          if token is None:
              raise HTTPException(status_code=403)

      @app.post("/signup")
      async def signup(_=Depends(require_feature)):
          return {}

      @app.post("/user")
      async def user(_=Depends(require_user)):
          return {}
      PY
    fastapi_requires({"main.py" => main}, "/signup")["auth"].should eq([["unresolved"]])
    fastapi_requires({"main.py" => main}, "/user")["auth"].should eq([["authenticated"]])
  end

  it "joins a dependency and a handler check, each tag carrying its own clauses" do
    main = <<-PY
      from fastapi import Depends, Header, HTTPException

      def get_current_user(token: str = Header(None)):
          if not token:
              raise HTTPException(status_code=401)
          return decode(token)

      @app.put("/items/{item_id}")
      async def update_item(item_id: int, current_user=Depends(get_current_user)):
          item = load(item_id)
          if item.owner_id != current_user.id:
              raise HTTPException(status_code=403)
          return item
      PY
    auth, authz = fastapi_endpoint({"main.py" => main}, "/items/{item_id}").tags
    auth.description.should eq("Protected by FastAPI Depends(get_current_user)")
    (auth.requires || [] of Access::Clause).map(&.any_of.map(&.to_s)).should eq([["authenticated"]])
    authz.description.should eq("Protected by FastAPI handler ownership/role check")
    (authz.requires || [] of Access::Clause).map(&.any_of.map(&.value)).should eq([["item.owner_id != current_user.id"]])
  end

  it "reads each mount of a router by the prefix that serves the URL" do
    main = <<-PY
      from fastapi import APIRouter, Depends, FastAPI, HTTPException
      from users import get_current_user

      def require_admin(user=Depends(get_current_user)):
          if user.role != "admin":
              raise HTTPException(status_code=403)

      def require_staff(user=Depends(get_current_user)):
          if user.role != "staff":
              raise HTTPException(status_code=403)

      app = FastAPI()
      shared = APIRouter(dependencies=[Depends(get_current_user)])

      @shared.get("/ping")
      async def ping():
          return {}

      app.include_router(shared, prefix="/v1")
      app.include_router(shared, prefix="/staff", dependencies=[Depends(require_staff)])
      app.include_router(shared, prefix="/admin", dependencies=[Depends(require_admin)])
      PY
    files = {"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}
    every_clause = ->(url : String) { fastapi_requires(files, url, "/ping").values.sum([] of Array(String)).uniq.sort! }
    every_clause.call("/admin/ping").should eq([["authenticated"], ["role:admin"]])
    every_clause.call("/staff/ping").should eq([["authenticated"], ["role:staff"]])
    # The open mount brings nothing of the others.
    every_clause.call("/v1/ping").should eq([["authenticated"]])
  end

  it "keeps an unresolved alternative when it cannot tell which mount serves the URL" do
    main = <<-PY
      from fastapi import APIRouter, Depends, FastAPI
      from users import get_current_user

      app = FastAPI()
      shared = APIRouter()

      @shared.get("/ping")
      async def ping():
          return {}

      app.include_router(shared, prefix=V1, dependencies=[Depends(get_current_user)])
      app.include_router(shared, prefix=V2, dependencies=[Security(get_current_user, scopes=["b"])])
      PY
    fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/x/ping", "/ping")["auth"]
      .should eq([["authenticated"], ["unresolved"]])
  end

  it "reads a router mounted many times without blowing up" do
    mounts = (0...12).map { |i| %(app.include_router(shared, prefix="/p#{i}", dependencies=[Security(get_current_user, scopes=["a#{i}", "b#{i}", "c#{i}"])])) }.join('\n')
    main = <<-PY
      from fastapi import APIRouter, FastAPI, Security
      from users import get_current_user

      app = FastAPI()
      shared = APIRouter()

      @shared.get("/x")
      async def x():
          return {}

      #{mounts}
      PY
    started = Time.instant
    requires = fastapi_requires({"users.py" => FASTAPI_REQUIRES_USERS, "main.py" => main}, "/p7/x", "/x")
    (Time.instant - started).should be < 5.seconds
    (requires["auth"]? || requires["authz"]).should contain(["scope:a7"])
  end

  it "marks a dependency a setting can lift" do
    main = <<-PY
      from fastapi import APIRouter, Depends, Header, HTTPException

      def create_token_dependency(expected: str | None):
          async def require_token(authorization: str | None = Header(default=None)) -> None:
              if expected is None:
                  return
              if authorization != expected:
                  raise HTTPException(status_code=401)

          return Depends(require_token)

      router = APIRouter(dependencies=[create_token_dependency(TOKEN)])

      @router.post("/collect")
      async def collect():
          return {}
      PY
    fastapi_requires({"main.py" => main}, "/collect")["auth"].should eq([["authenticated", "unresolved"]])
  end

  it "reads what an http middleware asserts" do
    main = <<-PY
      from fastapi import FastAPI
      from fastapi.responses import JSONResponse

      app = FastAPI()

      @app.middleware("http")
      async def gate(request, call_next):
          if not request.headers.get("authorization"):
              return JSONResponse(status_code=401, content={})
          return await call_next(request)

      @app.get("/dashboard")
      async def dashboard():
          return {}
      PY
    fastapi_requires({"main.py" => main}, "/dashboard")["auth"].should eq([["authenticated"]])
  end
end
