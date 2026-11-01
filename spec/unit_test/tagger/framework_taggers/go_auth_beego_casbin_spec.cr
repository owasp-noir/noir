require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

# A beego filter that authorizes every request against a Casbin policy
# (see `GoBeegoCasbinFilter`).
private def beego_guards(base : String, url : String, method : String = "GET", file : String = "routers/router.go") : Array(String)
  CodeLocator.instance.clear_all
  Dir.glob("#{base}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
  options = create_test_options
  options["base"] = YAML::Any.new(base)
  details = Details.new(PathInfo.new("#{base}/#{file}", 5))
  details.technology = "go_beego"
  endpoint = Endpoint.new(url, method, [] of Param, details)
  GoAuthTagger.new(options).perform([endpoint]).first.tags.select(&.name.in?("auth", "authz")).map(&.name)
end

private def with_beego_tree(files : Hash(String, String), &)
  dir = File.tempname("beego_casbin")
  files.each do |name, body|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

BEEGO_CASBIN_ROUTER_GO = <<-GO
  package routers

  import "github.com/beego/beego/v2/server/web"

  func InitAPI() {
      web.Router("/api/get-users", &controllers.ApiController{}, "GET:GetUsers")
  }
  GO

# `p, *, *, METHOD, PATH, *, *`: anonymous callers may call PATH.
BEEGO_CASBIN_POLICY_GO = <<-GO
  package authz

  import "github.com/casbin/casbin/v2"

  var Enforcer *casbin.Enforcer

  const modelText = `[request_definition]
  r = subOwner, subName, method, urlPath, objOwner, objName

  [policy_definition]
  p = subOwner, subName, method, urlPath, objOwner, objName
  `

  func InitApi() {
      ruleText := `
  p, built-in, *, *, *, *, *
  p, app, *, *, /api/get-token, *, *
  p, *, *, POST, /api/signup, *, *
  p, *, *, GET, /api/get-account, *, *
  p, *, *, *, /api/login/oauth, *, *
  p, *, *, GET, /.well-known/:application/jwks, *, *
  p, *, *, GET, /api/get-owned, built-in, *
  p, *, *, (GET)|(HEAD), /api/feed, *, *
  `
      _ = ruleText
  }

  func IsAllowed(subOwner, subName, method, urlPath, objOwner, objName string) bool {
      res, _ := Enforcer.Enforce(subOwner, subName, method, urlPath, objOwner, objName)
      return res
  }
  GO

private def casbin_filter_go(deny_branch : String, pattern : String = "*") : String
  <<-GO
    package routers

    import (
        "github.com/beego/beego/v2/server/web/context"
        "example.com/idp/authz"
    )

    func ApiFilter(ctx *context.Context) {
        allowed := authz.IsAllowed(getSubject(ctx), "", ctx.Request.Method, foldPath(ctx.Request.URL.Path), "", "")
        if !allowed {
            #{deny_branch}
        }
    }

    func foldPath(p string) string {
        if strings.HasPrefix(p, "/api/login/oauth") {
            return "/api/login/oauth"
        }
        return p
    }

    func denyRequest(ctx *context.Context) {
        ctx.Output.JSON(map[string]string{"status": "error", "msg": "Unauthorized operation"}, false, false)
    }

    func InitFilters() {
        web.InsertFilter("#{pattern}", web.BeforeRouter, ApiFilter)
    }
    GO
end

private def casbin_tree(deny_branch : String = "denyRequest(ctx)", pattern : String = "*") : Hash(String, String)
  {
    "go.mod"            => "module example.com/idp\n",
    "routers/router.go" => BEEGO_CASBIN_ROUTER_GO,
    "routers/filter.go" => casbin_filter_go(deny_branch, pattern),
    "authz/authz.go"    => BEEGO_CASBIN_POLICY_GO,
  }
end

describe "GoAuthTagger (beego Casbin filter)" do
  it "guards what the policy does not grant to anonymous callers" do
    with_beego_tree(casbin_tree) do |dir|
      beego_guards(dir, "/api/get-users").should eq(["auth"])
      beego_guards(dir, "/api/signup", "POST").should be_empty
      beego_guards(dir, "/api/get-account").should be_empty
    end
  end

  it "matches the policy's method, `:name` segments and the paths the filter folds" do
    with_beego_tree(casbin_tree) do |dir|
      # GET only is granted.
      beego_guards(dir, "/api/get-account", "POST").should eq(["auth"])
      beego_guards(dir, "/.well-known/:application/jwks").should be_empty
      beego_guards(dir, "/api/login/oauth/access_token", "POST").should be_empty
      # Only the folds the filter applies: `/api/get-account/x` is not `/api/get-account`.
      beego_guards(dir, "/api/get-account/export").should eq(["auth"])
      beego_guards(dir, "/api/feed").should be_empty
      beego_guards(dir, "/api/feed", "POST").should eq(["auth"])
    end
  end

  it "does not count a line for another subject, or one that fixes the object" do
    with_beego_tree(casbin_tree) do |dir|
      beego_guards(dir, "/api/get-token").should eq(["auth"])
      beego_guards(dir, "/api/get-owned").should eq(["auth"])
    end
  end

  it "reads the enforcer's own policy, not one of another module or package" do
    tree = casbin_tree
    other = BEEGO_CASBIN_POLICY_GO.sub("p, *, *, POST, /api/signup, *, *", "p, *, *, GET, /api/get-users, *, *")
    tree["tools/go.mod"] = "module example.com/tools\n"
    tree["tools/seed/seed.go"] = other.gsub("Enforcer.Enforce(", "seedEnforce(")
    tree["examples/demo.go"] = "package examples\n\nconst demo = `\n#{other.lines.select(&.starts_with?("p, ")).join("\n")}\n`\n"
    with_beego_tree(tree) do |dir|
      beego_guards(dir, "/api/get-users").should eq(["auth"])
    end
  end

  it "reads nothing from a filter that only logs a refused decision" do
    with_beego_tree(casbin_tree(%(logs.Warning("request denied")))) do |dir|
      beego_guards(dir, "/api/get-users").should be_empty
    end
  end

  it "applies a filter only under its pattern" do
    with_beego_tree(casbin_tree(pattern: "/admin/*")) do |dir|
      beego_guards(dir, "/api/get-users").should be_empty
      beego_guards(dir, "/admin/users").should eq(["auth"])
    end
  end

  it "reads nothing without a policy in the scan" do
    tree = casbin_tree
    tree["authz/authz.go"] = BEEGO_CASBIN_POLICY_GO.gsub(/ruleText := `[^`]*`/m, %(ruleText := ""))
    with_beego_tree(tree) do |dir|
      beego_guards(dir, "/api/get-users").should be_empty
    end
  end

  it "reads nothing from a filter that never asks the enforcer" do
    tree = casbin_tree
    tree["routers/filter.go"] = casbin_filter_go("denyRequest(ctx)").gsub("authz.IsAllowed(", "checkOrigin(")
    with_beego_tree(tree) do |dir|
      beego_guards(dir, "/api/get-users").should be_empty
    end
  end
end
