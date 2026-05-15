require "../../spec_helper"
require "../../../src/ai_context/augmentor"

def with_temp_ai_context_source(content : String, &block : String ->)
  path = "/tmp/noir-ai-context-#{Random.rand(1_000_000)}.txt"
  File.write(path, content)
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end

describe "NoirAIContext" do
  it "builds aggregated AI context from callees and tags" do
    source = <<-CODE
      app.post("/users/:id/avatar", requireAuth, async (req, res) => {
        const user = await User.find_by_sql(req.params.id)
        ParamsValidator.validate(req.body)
        return res.redirect(req.body.next)
      })
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/users/:id/avatar", "POST")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      details.technology = "js_express"
      endpoint.details = details

      id_param = Param.new("id", "1", "path")
      id_param.add_tag(Tag.new("idor", "This parameter may be vulnerable to Insecure Direct Object Reference (IDOR) attacks.", "Hunt"))
      endpoint.push_param(id_param)
      endpoint.push_param(Param.new("next", "/dashboard", "json"))
      endpoint.push_param(Param.new("file", "avatar.png", "form"))
      endpoint.push_callee(Callee.new("User.find_by_sql", path, 2))
      endpoint.push_callee(Callee.new("ParamsValidator.validate", path, 3))
      endpoint.push_callee(Callee.new("res.redirect", path, 4))
      endpoint.add_tag(Tag.new("auth", "Protected by Express requireAuth middleware", "express_auth"))
      endpoint.add_tag(Tag.new("jwt", "JWT endpoint for token-based authentication.", "JWT"))

      endpoints = NoirAIContext.apply([endpoint])

      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.guards.size.should eq(1)
      context.guards[0].source.should eq("express_auth")
      guard_snippet = context.guards[0].snippet
      guard_snippet.should_not be_nil
      guard_snippet.not_nil!.should contain("app.post")

      context.callees.map(&.name).should contain("User.find_by_sql")
      context.callees.first.snippet.should_not be_nil
      context.sinks.map(&.kind).should contain("sql")
      context.sinks.map(&.kind).should contain("redirect")
      context.validators.map(&.kind).should contain("validation")
      context.signals.map(&.kind).should contain("route_definition")
      context.signals.map(&.kind).should contain("path_param")
      context.signals.map(&.kind).should contain("redirect_input")
      context.signals.map(&.kind).should contain("file_input")
      context.signals.map(&.kind).should contain("idor")
      context.signals.map(&.name).should contain("jwt")
    end
  end

  it "adds low-confidence guard absence signals for unguarded state-changing endpoints" do
    source = <<-CODE
      post "/projects/:id/rotate" do
        rotate_secret(params[:id])
      end
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/projects/:id/rotate", "POST")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_param(Param.new("id", "7", "path"))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.signals.map(&.kind).should contain("guard_absence")
      context.signals.map(&.kind).should contain("idor_review")
    end
  end

  it "avoids broad sink false positives from request locals and non-template json renders" do
    source = <<-CODE
      def create_user(request)
        post = Post.new(request.POST.get("title"))
        return render json: post.save
      end
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/posts", "POST")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_callee(Callee.new("request.POST.get", path, 2))
      endpoint.push_callee(Callee.new("render", path, 3))
      endpoint.push_callee(Callee.new("post.save", path, 3))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.sinks.should be_empty
    end
  end

  it "avoids broad write/check heuristics for audit logs and health probes" do
    source = <<-CODE
      def status
        AuditLog.write("status")
        Health.check()
      end
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/status", "GET")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_callee(Callee.new("AuditLog.write", path, 2))
      endpoint.push_callee(Callee.new("Health.check", path, 3))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.sinks.should be_empty
      context.validators.should be_empty
    end
  end

  it "suppresses low-value identifier signals for bare POST body ids" do
    source = <<-CODE
      @PostMapping("/items")
      public Item createItem(@RequestBody Item item) { }
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/items", "POST")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_param(Param.new("id", "", "json"))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.signals.map(&.kind).should contain("state_change")
      context.signals.map(&.kind).should_not contain("identifier_input")
    end
  end

  it "prefers Hunt idor over generic identifier signals for path-based updates" do
    source = <<-CODE
      @PutMapping("/items/{id}")
      public Item updateItem(@PathVariable Long id, @RequestBody Item item) { }
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/items/{id}", "PUT")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      path_id = Param.new("id", "", "path")
      path_id.add_tag(Tag.new("idor", "This parameter may be vulnerable to Insecure Direct Object Reference (IDOR) attacks.", "Hunt"))
      endpoint.push_param(path_id)
      endpoint.push_param(Param.new("id", "", "json"))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.signals.map(&.kind).should_not contain("identifier_input")
      context.signals.map(&.kind).should contain("path_param")
      context.signals.map(&.kind).should contain("idor")
      context.signals.map(&.name).should contain("path.id")
    end
  end

  it "prefers Hunt sqli over generic query builder signals for the same param" do
    source = <<-CODE
      e.GET("/items/:itemId/reviews", func(c echo.Context) error {
        _ = c.QueryParam("sort")
        return c.JSON(http.StatusOK, nil)
      })
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/items/:itemId/reviews", "GET")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      sort_param = Param.new("sort", "", "query")
      sort_param.add_tag(Tag.new("sqli", "This parameter may be vulnerable to SQL Injection attacks.", "Hunt"))
      endpoint.push_param(sort_param)

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.signals.map(&.kind).should_not contain("query_builder_input")
      context.signals.map(&.kind).should contain("sqli")
      context.signals.map(&.name).should contain("query.sort")
    end
  end

  it "avoids treating generic user agent headers as identifier inputs" do
    source = <<-CODE
      r.Get("/api-test", func(w http.ResponseWriter, r *http.Request) {
        apiKey := r.Header.Get("X-API-Key")
        userAgent := r.Header.Get("User-Agent")
      })
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/api-test", "GET")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_param(Param.new("X-API-Key", "", "header"))
      endpoint.push_param(Param.new("User-Agent", "", "header"))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.signals.map(&.name).should contain("header.X-API-Key")
      context.signals.map(&.name).should_not contain("header.User-Agent")
    end
  end

  it "avoids treating request query accessors as sql sinks" do
    source = <<-CODE
      r.Get("/search-test", func(w http.ResponseWriter, r *http.Request) {
        query := r.URL.Query().Get("q")
        page := r.URL.Query().Get("page")
      })
      CODE

    with_temp_ai_context_source(source) do |path|
      endpoint = Endpoint.new("/search-test", "GET")
      details = endpoint.details
      details.add_path(PathInfo.new(path, 1))
      endpoint.details = details
      endpoint.push_callee(Callee.new("r.URL.Query", path, 2))
      endpoint.push_param(Param.new("q", "", "query"))
      endpoint.push_param(Param.new("page", "", "query"))

      endpoints = NoirAIContext.apply([endpoint])
      context = endpoints[0].ai_context
      context = context.should_not be_nil

      context.sinks.map(&.kind).should_not contain("sql")
    end
  end
end
