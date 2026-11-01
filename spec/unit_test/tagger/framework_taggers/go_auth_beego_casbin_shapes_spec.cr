require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

# Shapes a beego Casbin filter can take that do not guard what it seems to
# (see `GoBeegoCasbinFilter`), on a 3-field model (`p = sub, obj, act`).
private def casbin_shape_guards(base : String, url : String, file : String = "routers/router.go") : Array(String)
  CodeLocator.instance.clear_all
  Dir.glob("#{base}/**/*.{go,csv}").each { |f| CodeLocator.instance.register_path(f) }
  options = create_test_options
  options["base"] = YAML::Any.new(base)
  details = Details.new(PathInfo.new("#{base}/#{file}", 5))
  details.technology = "go_beego"
  endpoint = Endpoint.new(url, "GET", [] of Param, details)
  GoAuthTagger.new(options).perform([endpoint]).first.tags.select(&.name.in?("auth", "authz")).map(&.name)
end

private def with_casbin_shape(files : Hash(String, String), &)
  dir = File.tempname("beego_casbin_shape")
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

CASBIN_SHAPE_DEFAULT_BODY = <<-GO
    user := getUser(ctx)
    allowed := authz.IsAllowed(user, ctx.Request.URL.Path, ctx.Request.Method)
    if !allowed {
      denyRequest(ctx)
    }
  GO

CASBIN_SHAPE_GET_USER = <<-GO
  func getUser(ctx *context.Context) string {
    u, _ := ctx.Input.Session("user").(string)
    if u == "" {
      return "anonymous"
    }
    return u
  }
  GO

private def casbin_shape(insert : String = %(web.InsertFilter("*", web.BeforeRouter, routers.ApiFilter)),
                         body : String = CASBIN_SHAPE_DEFAULT_BODY, definition : String = "sub, obj, act",
                         effect : String = "some(where (p.eft == allow))", rules : String = "p, *, /api/public, GET",
                         get_user : Bool = true) : Hash(String, String)
  {
    "go.mod"  => "module example.com/app\n",
    "main.go" => <<-GO,
      package main

      import (
        "github.com/beego/beego/v2/server/web"
        "example.com/app/routers"
      )

      func main() {
        #{insert}
        web.Run()
      }
      GO
    "routers/router.go" => <<-GO,
      package routers

      import "example.com/app/controllers"

      func init() {
        web.Router("/api/public", &controllers.ApiController{}, "get:Public")
      }
      GO
    "routers/filter.go" => <<-GO,
      package routers

      import (
        "github.com/beego/beego/v2/server/web/context"
        "example.com/app/authz"
      )

      func ApiFilter(ctx *context.Context) {
      #{body}
      }

      func denyRequest(ctx *context.Context) {
        ctx.Output.SetStatus(403)
      }

      #{get_user ? CASBIN_SHAPE_GET_USER : ""}
      GO
    "authz/authz.go" => <<-GO,
      package authz

      const modelText = `[request_definition]
      r = sub, obj, act

      [policy_definition]
      p = #{definition}

      [policy_effect]
      e = #{effect}
      `

      const ruleText = `
      #{rules}
      `

      func IsAllowed(sub, obj, act string) bool {
        ok, _ := Enforcer.Enforce(sub, obj, act)
        return ok
      }
      GO
  }
end

private def deny_body(branch : String) : String
  CASBIN_SHAPE_DEFAULT_BODY.sub("denyRequest(ctx)", branch)
end

describe "GoAuthTagger (beego Casbin filter shapes)" do
  it "reads only a filter that runs before the controller" do
    with_casbin_shape(casbin_shape) { |dir| casbin_shape_guards(dir, "/api/secret").should eq(["auth"]) }
    with_casbin_shape(casbin_shape(%(web.InsertFilter("*", web.BeforeExec, routers.ApiFilter)))) { |dir| casbin_shape_guards(dir, "/api/secret").should eq(["auth"]) }
    with_casbin_shape(casbin_shape(%(web.InsertFilter("*", web.AfterExec, routers.ApiFilter)))) { |dir| casbin_shape_guards(dir, "/api/secret").should be_empty }
    with_casbin_shape(casbin_shape(%(web.InsertFilter("*", web.FinishRouter, routers.ApiFilter)))) { |dir| casbin_shape_guards(dir, "/api/secret").should be_empty }
  end

  it "keeps each live registration's own pattern and skips a commented one" do
    commented = %(// web.InsertFilter("*", web.BeforeRouter, routers.ApiFilter)\n  web.InsertFilter("/admin/*", web.BeforeRouter, routers.ApiFilter))
    with_casbin_shape(casbin_shape(commented)) do |dir|
      casbin_shape_guards(dir, "/api/secret").should be_empty
      casbin_shape_guards(dir, "/admin/users").should eq(["auth"])
    end
    two = %(web.InsertFilter("/api/*", web.BeforeRouter, routers.ApiFilter)\n  web.InsertFilter("/admin/*", web.BeforeRouter, routers.ApiFilter))
    with_casbin_shape(casbin_shape(two)) do |dir|
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
      casbin_shape_guards(dir, "/admin/users").should eq(["auth"])
      casbin_shape_guards(dir, "/other").should be_empty
    end
  end

  it "needs a written response under the refused decision, not a flag, a comment or a bare return" do
    [%(ctx.Input.SetData("denied", true)),
     %(// unauthorized: the controller decides\n    ctx.Input.SetData("authz", false)),
     %(return // unauthorized)].each do |branch|
      with_casbin_shape(casbin_shape(body: deny_body(branch))) { |dir| casbin_shape_guards(dir, "/api/secret").should be_empty }
    end
  end

  it "reads nothing when a request without a credential returns before the check" do
    body = <<-GO
        token := ctx.Input.Header("Authorization")
        if token == "" {
          return
        }
        allowed := authz.IsAllowed(token, ctx.Request.URL.Path, ctx.Request.Method)
        if !allowed {
          denyRequest(ctx)
        }
      GO
    with_casbin_shape(casbin_shape(body: body, get_user: false)) { |dir| casbin_shape_guards(dir, "/api/secret").should be_empty }
  end

  it "reads the subject the filter passes without a session, and its roles" do
    body = <<-GO
        user, _ := ctx.Input.Session("user").(string)
        if user == "" {
          user = "guest"
        }
        allowed := authz.IsAllowed(user, ctx.Request.URL.Path, ctx.Request.Method)
        if !allowed {
          denyRequest(ctx)
        }
      GO
    with_casbin_shape(casbin_shape(body: body, rules: "p, guest, /api/public, GET\np, admin, /admin/*, GET", get_user: false)) do |dir|
      casbin_shape_guards(dir, "/api/public").should be_empty
      casbin_shape_guards(dir, "/admin/users").should eq(["auth"])
    end
    with_casbin_shape(casbin_shape(rules: "p, public_role, /api/public, GET\ng, anonymous, public_role")) do |dir|
      casbin_shape_guards(dir, "/api/public").should be_empty
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
    end
  end

  it "grants nothing with a deny row, and reads no filter under a deny-override effect" do
    with_casbin_shape(casbin_shape(definition: "sub, obj, act, eft", rules: "p, *, /api/public, GET, allow\np, *, /api/secret, GET, deny")) do |dir|
      casbin_shape_guards(dir, "/api/public").should be_empty
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
    end
    with_casbin_shape(casbin_shape(definition: "sub, obj, act, eft", effect: "!some(where (p.eft == deny))", rules: "p, *, /admin/*, GET, deny")) do |dir|
      casbin_shape_guards(dir, "/api/secret").should be_empty
    end
  end

  it "compares a path exactly when the filter folds nothing" do
    with_casbin_shape(casbin_shape) { |dir| casbin_shape_guards(dir, "/api/public/export").should eq(["auth"]) }
  end

  it "guards only the program that registers the filter" do
    tree = casbin_shape
    tree["cmd/admin/main.go"] = <<-GO
      package main

      import "github.com/beego/beego/v2/server/web"

      func main() {
        web.Router("/internal/stats", &StatsController{}, "get:Get")
        web.Run(":9090")
      }
      GO
    with_casbin_shape(tree) do |dir|
      casbin_shape_guards(dir, "/internal/stats", "cmd/admin/main.go").should be_empty
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
    end
  end

  it "falls back to a policy file when no Go raw string holds `p,` lines" do
    tree = casbin_shape(rules: "")
    tree["conf/policy.csv"] = "p, *, /api/public, GET\np, admin, /admin/*, GET\n"
    tree["util/u.go"] = <<-GO
      package util

      func N(s string) int {
        p, err := strconv.Atoi(s)
        if err != nil {
          return 0
        }
        return p
      }
      GO
    with_casbin_shape(tree) do |dir|
      casbin_shape_guards(dir, "/api/public").should be_empty
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
    end
  end

  it "counts only a write on the request, not a log line or a builder's WriteString" do
    report = <<-GO
      package routers

      import (
        "strings"

        "github.com/beego/beego/v2/core/logs"
        "github.com/beego/beego/v2/server/web/context"
      )

      func report(ctx *context.Context) {
        audit(ctx.Request.URL.Path)
      }

      func audit(path string) {
        var sb strings.Builder
        sb.WriteString("refused ")
        sb.WriteString(path)
        logs.Warning(sb.String())
      }
      GO
    tree = casbin_shape(body: deny_body("report(ctx)"))
    tree["routers/log.go"] = report
    with_casbin_shape(tree) { |dir| casbin_shape_guards(dir, "/api/secret").should be_empty }
    with_casbin_shape(casbin_shape(body: deny_body(%(logs.Warning("authz refused %s", ctx.Request.URL.Path, 403))))) do |dir|
      casbin_shape_guards(dir, "/api/secret").should be_empty
    end
    # Handed the context two hops down, the write still counts.
    deny = "func deny(ctx *context.Context) {\n  respond(ctx)\n}\n\nfunc respond(c *context.Context) {\n  c.Output.SetStatus(403)\n}\n"
    tree = casbin_shape(body: deny_body("deny(ctx)"))
    tree["routers/deny.go"] = "package routers\n\nimport \"github.com/beego/beego/v2/server/web/context\"\n\n#{deny}"
    with_casbin_shape(tree) { |dir| casbin_shape_guards(dir, "/api/secret").should eq(["auth"]) }
  end

  it "follows a role chain, and not one that starts at another subject" do
    with_casbin_shape(casbin_shape(rules: "p, reader, /api/public, GET\ng, anonymous, viewer\ng, viewer, reader")) do |dir|
      casbin_shape_guards(dir, "/api/public").should be_empty
    end
    with_casbin_shape(casbin_shape(rules: "p, reader, /api/public, GET\ng, alice, viewer\ng, viewer, reader")) do |dir|
      casbin_shape_guards(dir, "/api/public").should eq(["auth"])
    end
  end

  it "guards a program only if it runs the registration" do
    tree = casbin_shape("routers.InitFilters()")
    tree["routers/init.go"] = "package routers\n\nimport \"github.com/beego/beego/v2/server/web\"\n\nfunc InitFilters() {\n  web.InsertFilter(\"*\", web.BeforeRouter, ApiFilter)\n}\n"
    tree["cmd/admin/main.go"] = <<-GO
      package main

      import (
        "github.com/beego/beego/v2/server/web"
        _ "example.com/app/routers"
      )

      func main() {
        web.Router("/internal/stats", &StatsController{}, "get:Get")
        web.Run(":9090")
      }
      GO
    with_casbin_shape(tree) do |dir|
      casbin_shape_guards(dir, "/api/secret").should eq(["auth"])
      casbin_shape_guards(dir, "/internal/stats", "cmd/admin/main.go").should be_empty
    end
    # An `init()` registration runs in every program that imports it.
    tree["routers/init.go"] = tree["routers/init.go"].sub("func InitFilters()", "func init()")
    tree["main.go"] = tree["main.go"].sub("routers.InitFilters()", "")
    with_casbin_shape(tree) do |dir|
      casbin_shape_guards(dir, "/internal/stats", "cmd/admin/main.go").should eq(["auth"])
    end
  end

  it "reads thousands of registrations in linear time" do
    lines = (1..3000).map { |i| %(web.InsertFilter("/r#{i}/*", web.BeforeRouter, routers.ApiFilter)) }.join("\n  ")
    with_casbin_shape(casbin_shape(lines)) do |dir|
      elapsed = Time.measure { casbin_shape_guards(dir, "/r2999/x").should eq(["auth"]) }
      elapsed.total_seconds.should be < 5
    end
  end
end
