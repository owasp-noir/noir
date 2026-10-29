require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# The URLs `RustAuthTagger` guards when each is mounted from the first file.
private def axum_guarded_urls(files : Hash(String, String), urls : Array(String)) : Array(String)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("axum_layers")
  files.each do |rel, src|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, src)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  main = File.join(tmpdir, files.keys.first)
  endpoints = urls.map { |url| Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(main, 1)).tap(&.technology=("rust_axum"))) }
  RustAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.reject(&.tags.empty?).map(&.url).sort!
end

AXUM_REQUIRE_AUTH = <<-RUST
  async fn require_auth(req: Request, next: Next) -> Result<Response, StatusCode> {
      if req.headers().get("authorization").is_none() {
          return Err(StatusCode::UNAUTHORIZED);
      }
      Ok(next.run(req).await)
  }

  RUST

describe "RustAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/rust/actix_auth", __DIR__)
  main_path = "#{fixture_base}/src/main.rs"

  # main.rs line reference:
  #  6: #[get("/health")]
  #  7: async fn health() -> HttpResponse {
  # 12: #[get("/public")]
  # 13: async fn public_page() -> HttpResponse {
  # 18: #[get("/profile")]
  # 19: async fn profile(auth: BearerAuth) -> HttpResponse {
  # 24: #[guard = "AdminGuard"]
  # 25: #[get("/admin/users")]
  # 26: async fn admin_users() -> HttpResponse {
  # 31: #[post("/api/posts")]
  # 32: async fn create_post(user: AuthUser, body: web::Json<PostData>) -> HttpResponse {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects BearerAuth extractor in function signature" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(main_path, 18))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("rust_auth")
    endpoint.tags[0].description.should contain("BearerAuth")
  end

  it "detects #[guard] attribute" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(main_path, 25))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/admin/users", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("guard")
  end

  it "detects AuthUser guard type in function signature" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(main_path, 31))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/api/posts", "POST", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AuthUser")
  end

  it "does not tag public endpoints" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(main_path, 6))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag public_page endpoint" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(main_path, 12))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "applies an Axum layer to every route above it in the chain, and only those" do
    tmpdir = File.tempname("axum_layer")
    Dir.mkdir_p(File.join(tmpdir, "src"))
    main_rs = File.join(tmpdir, "src", "main.rs")
    File.write(main_rs, [
      "fn app() -> Router {",
      "    let protected = Router::new()",
      "        .route(\"/me\", get(me))",
      "        .route(\"/admin\", get(admin))",
      "        .route_layer(middleware::from_fn_with_state(state.clone(), auth))",
      "        .route(\"/login\", post(login))",
      "        .route(\"/\", get(root));",
      "    let api = Router::new()",
      "        .route(\"/a\", get(a))",
      "        .route(\"/b\", get(b))",
      "        .layer(middleware::from_fn(auth))",
      "        .route(\"/c\", get(c));",
      "    protected.merge(api)",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)

    urls = {"/me" => 3, "/admin" => 4, "/login" => 6, "/" => 7, "/a" => 9, "/b" => 10, "/c" => 12}
    endpoints = urls.map do |url, line|
      details = Details.new(PathInfo.new(main_rs, line))
      details.technology = "rust_axum"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    RustAuthTagger.new(noir_options).perform(endpoints)

    tagged = endpoints.reject(&.tags.empty?).map(&.url)
    tagged.should eq(["/me", "/admin", "/a", "/b"])

    FileUtils.rm_rf(tmpdir)
  end

  it "keeps an Axum layer's tag when the layered router is nested under a prefix" do
    tmpdir = File.tempname("axum_layer_nest")
    Dir.mkdir_p(File.join(tmpdir, "src"))
    main_rs = File.join(tmpdir, "src", "main.rs")
    File.write(main_rs, [
      "fn app() -> Router {",
      "    let api = Router::new()",
      "        .route(\"/users\", get(list))",
      "        .layer(middleware::from_fn(require_auth));",
      "    Router::new().nest(\"/api\", api).route(\"/health\", get(health))",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)

    endpoints = [{"/api/users", 3}, {"/health", 5}].map do |url, line|
      details = Details.new(PathInfo.new(main_rs, line))
      details.technology = "rust_axum"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    RustAuthTagger.new(noir_options).perform(endpoints)

    endpoints.reject(&.tags.empty?).map(&.url).should eq(["/api/users"])

    FileUtils.rm_rf(tmpdir)
  end

  it "follows Axum route_layer across functions and merges across modules (Issue #3265 item 1)" do
    tmpdir = File.tempname("axum_layer_merge")
    Dir.mkdir_p(File.join(tmpdir, "src", "web"))
    main_rs = File.join(tmpdir, "src", "main.rs")
    items_rs = File.join(tmpdir, "src", "web", "items.rs")
    health_rs = File.join(tmpdir, "src", "web", "health.rs")

    File.write(main_rs, [
      "async fn require_auth(req: Request, next: Next) -> Result<Response, StatusCode> {",
      "    if req.headers().get(\"authorization\").is_none() {",
      "        return Err(StatusCode::UNAUTHORIZED);",
      "    }",
      "    Ok(next.run(req).await)",
      "}",
      "",
      "fn protected() -> Router {",
      "    Router::new()",
      "        .merge(web::items::routes())",
      "        .route(\"/orders\", get(orders))",
      "}",
      "",
      "#[tokio::main]",
      "async fn main() {",
      "    let app = protected()",
      "        .route_layer(middleware::from_fn(require_auth))",
      "        .merge(web::health::routes());",
      "}",
    ].join("\n"))

    File.write(items_rs, [
      "pub fn routes() -> Router {",
      "    Router::new().route(\"/items\", get(list_items))",
      "}",
    ].join("\n"))

    File.write(health_rs, [
      "pub fn routes() -> Router {",
      "    Router::new().route(\"/up\", get(up))",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)
    CodeLocator.instance.register_path(items_rs)
    CodeLocator.instance.register_path(health_rs)

    endpoints = [
      Endpoint.new("/orders", "GET", [] of Param, Details.new(PathInfo.new(main_rs, 11)).tap(&.technology=("rust_axum"))),
      Endpoint.new("/items", "GET", [] of Param, Details.new(PathInfo.new(items_rs, 2)).tap(&.technology=("rust_axum"))),
      Endpoint.new("/up", "GET", [] of Param, Details.new(PathInfo.new(health_rs, 2)).tap(&.technology=("rust_axum"))),
    ]

    RustAuthTagger.new(noir_options).perform(endpoints)

    tagged = endpoints.reject(&.tags.empty?).map(&.url)
    tagged.sort.should eq(["/items", "/orders"])

    FileUtils.rm_rf(tmpdir)
  end

  it "detects from_fn_with_state wrapped over multiple lines (Issue #3265 item 2)" do
    tmpdir = File.tempname("axum_multiline_from_fn")
    Dir.mkdir_p(File.join(tmpdir, "src"))
    main_rs = File.join(tmpdir, "src", "main.rs")

    File.write(main_rs, [
      "fn app() -> Router {",
      "    let app = Router::new()",
      "        .route(\"/orders\", get(orders))",
      "        .route_layer(middleware::from_fn_with_state(",
      "            state.clone(),",
      "            auth::middleware,",
      "        ))",
      "        .with_state(state);",
      "    app",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)

    endpoints = [
      Endpoint.new("/orders", "GET", [] of Param, Details.new(PathInfo.new(main_rs, 3)).tap(&.technology=("rust_axum"))),
    ]

    RustAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.empty?.should be_false
    endpoints[0].tags[0].name.should eq("auth")
    endpoints[0].tags[0].description.should contain("/orders")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not tag routes wrapped by a CSRF-only middleware even in an auth module (Issue #3265 item 3)" do
    tmpdir = File.tempname("axum_csrf_middleware")
    Dir.mkdir_p(File.join(tmpdir, "src"))
    main_rs = File.join(tmpdir, "src", "main.rs")

    File.write(main_rs, [
      "mod auth {",
      "    pub mod csrf {",
      "        use super::super::*;",
      "        pub async fn middleware(State(_s): State<()>, req: Request, next: Next) -> Result<Response, StatusCode> {",
      "            if req.headers().get(\"x-csrf-token\").is_none() {",
      "                return Err(StatusCode::FORBIDDEN);",
      "            }",
      "            Ok(next.run(req).await)",
      "        }",
      "    }",
      "}",
      "",
      "fn app() -> Router {",
      "    let app = Router::new()",
      "        .route(\"/orders\", post(create_order))",
      "        .route_layer(middleware::from_fn_with_state(state.clone(), auth::csrf::middleware))",
      "        .with_state(state);",
      "    app",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)

    endpoints = [
      Endpoint.new("/orders", "POST", [] of Param, Details.new(PathInfo.new(main_rs, 15)).tap(&.technology=("rust_axum"))),
    ]

    RustAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.empty?.should be_true

    FileUtils.rm_rf(tmpdir)
  end

  it "tags route when middleware function body refuses unauthenticated caller even if not named auth" do
    tmpdir = File.tempname("axum_body_guard")
    Dir.mkdir_p(File.join(tmpdir, "src"))
    main_rs = File.join(tmpdir, "src", "main.rs")

    File.write(main_rs, [
      "async fn check_token(req: Request, next: Next) -> Result<Response, StatusCode> {",
      "    if req.headers().get(\"authorization\").is_none() {",
      "        return Err(StatusCode::UNAUTHORIZED);",
      "    }",
      "    Ok(next.run(req).await)",
      "}",
      "",
      "fn app() -> Router {",
      "    Router::new()",
      "        .route(\"/secure\", get(secure_handler))",
      "        .route_layer(middleware::from_fn(check_token))",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.register_path(main_rs)

    endpoints = [
      Endpoint.new("/secure", "GET", [] of Param, Details.new(PathInfo.new(main_rs, 10)).tap(&.technology=("rust_axum"))),
    ]

    RustAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.empty?.should be_false
    endpoints[0].tags[0].name.should eq("auth")

    FileUtils.rm_rf(tmpdir)
  end

  it "reads a `let` router binding in its own fn and scope, never a later or same-named one" do
    src = AXUM_REQUIRE_AUTH + <<-RUST
      fn public_routes() -> Router {
          let router = Router::new().route("/health", get(h));
          router
      }
      fn private_routes() -> Router {
          let router = Router::new().route("/admin", get(a));
          router.route_layer(middleware::from_fn(require_auth))
      }
      fn build() -> Router {
          let app = Router::new().route("/a", get(a));
          let app = app.route("/b", get(b));
          let app = app.route_layer(middleware::from_fn(require_auth));
          app.route("/c", get(c))
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/health", "/admin", "/a", "/b", "/c"]).should eq(["/a", "/admin", "/b"])
  end

  it "does not read a Router parameter as the same-named fn" do
    src = AXUM_REQUIRE_AUTH + <<-RUST
      fn app() -> Router {
          Router::new().route("/open", get(o))
      }
      fn with_auth(app: Router) -> Router {
          let app = app.route_layer(middleware::from_fn(require_auth));
          app
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/open"]).should be_empty
  end

  it "judges only the constructor of a non-`from_fn` layer by name" do
    src = <<-RUST
      fn app() -> Router {
          let open = Router::new()
              .route("/open", get(o))
              .layer(Extension(oauth_client))
              .layer(SessionManagerLayer::new(store))
              .layer(SetSensitiveRequestHeadersLayer::new(once(AUTHORIZATION)));
          Router::new().route("/me", get(me)).layer(AuthLayer::new(keys)).merge(open)
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/open", "/me"]).should eq(["/me"])
  end

  it "judges a middleware found in the scan by its body, not its name" do
    src = <<-RUST
      async fn auth_logger(req: Request, next: Next) -> Response {
          // would return 401 if StatusCode::UNAUTHORIZED were wired
          tracing::info!("authorization: {:?}", req.headers().get("authorization"));
          next.run(req).await
      }
      async fn rate_limit(req: Request, next: Next) -> Response {
          if too_many(req.headers().get("user-agent")) {
              return StatusCode::TOO_MANY_REQUESTS.into_response();
          }
          next.run(req).await
      }
      async fn auth_session(req: Request, next: Next) -> Result<Response, AppError> {
          let token = req.headers().get("authorization").ok_or(AppError::Session)?;
          Ok(next.run(req).await)
      }
      fn app() -> Router {
          Router::new()
              .route("/logged", get(a))
              .route_layer(middleware::from_fn(auth_logger))
              .merge(Router::new().route("/limited", get(b)).route_layer(middleware::from_fn(rate_limit)))
              .merge(Router::new().route("/session", get(c)).route_layer(middleware::from_fn(auth_session)))
              .merge(Router::new().route("/inline", get(d)).route_layer(middleware::from_fn(|req: Request, next: Next| async move {
                  if req.headers().get("authorization").is_none() {
                      return Err(StatusCode::UNAUTHORIZED);
                  }
                  Ok(next.run(req).await)
              })))
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/logged", "/limited", "/session", "/inline"]).should eq(["/inline", "/session"])
  end

  it "guards with a middleware that extracts a refusing guard, also through `Result` and `?`" do
    src = <<-RUST
      struct CurrentUser;
      impl<S> FromRequestParts<S> for CurrentUser {
          type Rejection = AppError;
          async fn from_request_parts(parts: &mut Parts, _s: &S) -> Result<Self, AppError> {
              parts.extensions.get::<CurrentUser>().cloned().ok_or(AppError::NoCtx)
          }
      }
      impl ResponseError for AppError {
          fn status_code(&self) -> StatusCode {
              match self {
                  AppError::NoCtx => StatusCode::FORBIDDEN,
              }
          }
      }
      async fn require_login(_user: CurrentUser, req: Request, next: Next) -> Response {
          next.run(req).await
      }
      async fn mw_ctx_require(ctx: Result<CurrentUser>, req: Request, next: Next) -> Result<Response> {
          debug!("{ctx:?}");
          ctx?;
          Ok(next.run(req).await)
      }
      async fn mw_ctx_resolve(ctx: Result<CurrentUser>, req: Request, next: Next) -> Response {
          debug!("{ctx:?}");
          next.run(req).await
      }
      fn app() -> Router {
          Router::new()
              .route("/login", get(a))
              .route_layer(middleware::from_fn(require_login))
              .merge(Router::new().route("/rpc", post(b)).route_layer(middleware::from_fn(mw_ctx_require)))
              .merge(Router::new().route("/open", get(c)).route_layer(middleware::from_fn(mw_ctx_resolve)))
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/login", "/rpc", "/open"]).should eq(["/login", "/rpc"])
  end

  it "reads the mounts of the called fn only, not a same-named fn in another mod" do
    src = AXUM_REQUIRE_AUTH + <<-RUST
      mod a {
          pub fn routes() -> Router { Router::new().route("/a", get(a)) }
      }
      mod b {
          pub fn routes() -> Router { Router::new().route("/b", get(b)) }
      }
      fn app() -> Router {
          a::routes().route_layer(middleware::from_fn(require_auth)).merge(b::routes())
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/a", "/b"]).should eq(["/a"])
  end

  it "does not read a 401 the middleware only compares against as a refusal" do
    src = <<-RUST
      async fn auth_metrics(req: Request, next: Next) -> Response {
          let res = next.run(req).await;
          if res.status() == StatusCode::UNAUTHORIZED || StatusCode::FORBIDDEN != res.status() {
              counter!("denied").increment(1);
          }
          res
      }
      fn app() -> Router {
          Router::new().route("/a", get(a)).route_layer(middleware::from_fn(auth_metrics))
      }
      RUST
    axum_guarded_urls({"src/main.rs" => src}, ["/a"]).should be_empty
  end

  # rust10x/rust-web-app (Issue #3265): the middleware lives in another
  # workspace crate and refuses only through `ctx?`, whose error maps to 403
  # in a `&self` helper of that crate's `Error`.
  it "guards a route_layer middleware imported from another workspace crate" do
    main = <<-RUST
      use lib_web::middleware::mw_auth::{mw_ctx_require, mw_ctx_peek};
      use axum::{middleware, Router};
      fn app() -> Router {
          let routes_rpc = web::routes_rpc::routes(mm.clone())
              .route_layer(middleware::from_fn(mw_ctx_require));
          let routes_peek = web::routes_peek::routes()
              .route_layer(middleware::from_fn(mw_ctx_peek));
          Router::new()
              .merge(routes_login::routes(mm.clone()))
              .nest("/api", routes_rpc)
              .nest("/api", routes_peek)
      }
      RUST
    mw = <<-RUST
      pub async fn mw_ctx_require(ctx: Result<CtxW>, req: Request<Body>, next: Next) -> Result<Response> {
          debug!("{:<12} - mw_ctx_require - {ctx:?}", "MIDDLEWARE");
          ctx?;
          Ok(next.run(req).await)
      }
      pub async fn mw_ctx_peek(ctx: Result<CtxW>, req: Request<Body>, next: Next) -> Response {
          let _ctx = ctx.ok();
          next.run(req).await
      }
      impl<S: Send + Sync> FromRequestParts<S> for CtxW {
          type Rejection = Error;
          async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self> {
              parts.extensions.get::<CtxExtResult>().ok_or(Error::CtxExt(CtxExtError::CtxNotInRequestExt))?.clone().map_err(Error::CtxExt)
          }
      }
      RUST
    error = <<-RUST
      impl Error {
          pub fn client_status_and_error(&self) -> (StatusCode, ClientError) {
              use Error::*;
              match self {
                  CtxExt(_) => (StatusCode::FORBIDDEN, ClientError::NO_AUTH),
                  _ => (StatusCode::INTERNAL_SERVER_ERROR, ClientError::SERVICE_ERROR),
              }
          }
      }
      RUST
    # A same-named fn in another crate that does not refuse: only the
    # imported crate's definition counts.
    decoy = <<-RUST
      pub async fn mw_ctx_require(req: Request<Body>, next: Next) -> Response {
          next.run(req).await
      }
      RUST
    files = {
      "crates/services/web-server/src/main.rs"             => main,
      "crates/services/web-server/src/web/routes_rpc.rs"   => %(pub fn routes(mm: ModelManager) -> Router { Router::new().route("/rpc", post(rpc)) }),
      "crates/services/web-server/src/web/routes_peek.rs"  => %(pub fn routes() -> Router { Router::new().route("/peek", post(peek)) }),
      "crates/services/web-server/src/web/routes_login.rs" => %(pub fn routes(mm: ModelManager) -> Router { Router::new().route("/api/login", post(login)) }),
      "crates/libs/lib-web/src/middleware/mw_auth.rs"      => mw,
      "crates/libs/lib-web/src/error.rs"                   => error,
      "crates/libs/lib-decoy/src/middleware/mw_auth.rs"    => decoy,
    }
    axum_guarded_urls(files, ["/api/rpc", "/api/peek", "/api/login"]).should eq(["/api/rpc"])

    files["crates/services/web-server/src/main.rs"] = main.sub("lib_web::", "lib_decoy::")
    axum_guarded_urls(files, ["/api/rpc", "/api/peek", "/api/login"]).should be_empty
  end

  it "resolves a crate import to the crate of the importing app in a monorepo" do
    refusing = <<-RUST
      pub async fn mw_ctx(req: Request<Body>, next: Next) -> Result<Response, StatusCode> {
          if req.headers().get("authorization").is_none() {
              return Err(StatusCode::FORBIDDEN);
          }
          Ok(next.run(req).await)
      }
      RUST
    reading = <<-RUST
      pub async fn mw_ctx(req: Request<Body>, next: Next) -> Result<Response, StatusCode> {
          tracing::debug!("{}", req.uri());
          Ok(next.run(req).await)
      }
      RUST
    main = <<-RUST
      use web::mw::mw_ctx;
      fn app() -> Router {
          Router::new().route("/rpc", post(handler)).route_layer(middleware::from_fn(mw_ctx))
      }
      RUST
    {"app_a" => {refusing, ["/rpc"]}, "app_b" => {reading, [] of String}}.each do |app, (mw, guarded)|
      other = app == "app_a" ? "app_b" : "app_a"
      files = {
        "#{app}/crates/server/src/main.rs" => main,
        "#{app}/crates/web/src/mw.rs"      => mw,
        "#{other}/crates/web/src/mw.rs"    => mw == refusing ? reading : refusing,
      }
      axum_guarded_urls(files, ["/rpc"]).should eq(guarded)
    end

    # Two crates as near as each other: neither is read.
    files = {
      "server/src/main.rs" => main,
      "a/web/src/mw.rs"    => refusing,
      "b/web/src/mw.rs"    => refusing,
    }
    axum_guarded_urls(files, ["/rpc"]).should be_empty
  end

  it "guards with a middleware from another crate that redirects to a login page" do
    main = <<-RUST
      use lib_auth::require_auth;
      fn app() -> Router {
          Router::new().route("/admin", post(handler)).route_layer(middleware::from_fn(require_auth))
      }
      RUST
    mw = <<-RUST
      pub async fn require_auth(req: Request<Body>, next: Next) -> Response {
          match req.headers().get("cookie") {
              Some(_) => next.run(req).await,
              None => Redirect::to("/login").into_response(),
          }
      }
      RUST
    files = {"crates/server/src/main.rs" => main, "crates/lib-auth/src/lib.rs" => mw}
    axum_guarded_urls(files, ["/admin"]).should eq(["/admin"])

    files["crates/lib-auth/src/lib.rs"] = mw.sub(%("/login"), %("/v2/admin"))
    axum_guarded_urls(files, ["/admin"]).should be_empty
  end
end

describe "RustAuthTagger request guards read from their FromRequest impls" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/rust/rocket_guards", __DIR__)
  main_path = "#{fixture_base}/src/main.rs"

  tag_handler = ->(name : String, line : Int32) do
    CodeLocator.instance.clear_all
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    Dir.glob("#{fixture_base}/**/*").each { |f| CodeLocator.instance.register_path(f) unless File.directory?(f) }

    details = Details.new(PathInfo.new(main_path, line - 1))
    details.technology = "rust_rocket"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)
    endpoint.handler = Handler.new(name, main_path, line)
    RustAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.map(&.description)
  end

  # Handler fn lines in main.rs (the `fn` line `Endpoint#handler` names).
  it "tags a guard whose impl refuses through a 401 macro_rules!" do
    tag_handler.call("me", 30).should eq(["Protected by Rust Session request guard"])
    tag_handler.call("events", 67).should eq(["Protected by Rust Session request guard"])
  end

  it "tags a guard that forwards another guard's failure" do
    tag_handler.call("delete_org", 37).should eq(["Protected by Rust OrgSession request guard"])
  end

  it "leaves a guard anonymous when it refuses only after a never-failing guard fails" do
    tag_handler.call("client", 42).should be_empty
  end

  it "leaves an Option-wrapped guard anonymous" do
    tag_handler.call("maybe", 47).should be_empty
  end

  it "does not trust a guard-like name whose impl only answers 400" do
    tag_handler.call("hint", 52).should be_empty
  end
end

describe "RustAuthTagger actix extractors that fail with a 401 error variant" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/rust/actix_crossfile_handler", __DIR__)

  tag_handler = ->(file : String, name : String, line : Int32) do
    CodeLocator.instance.clear_all
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    Dir.glob("#{fixture_base}/**/*").each { |f| CodeLocator.instance.register_path(f) unless File.directory?(f) }

    path = "#{fixture_base}/api/src/#{file}"
    details = Details.new(PathInfo.new("#{fixture_base}/server/src/main.rs", 12))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)
    endpoint.handler = Handler.new(name, path, line)
    RustAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.map(&.description)
  end

  # `Err(AppError::NotLoggedIn)` where `ResponseError::status_code` maps
  # `AppError::NotLoggedIn => StatusCode::UNAUTHORIZED`.
  it "tags a required extractor whose impl errs with a 401 variant" do
    tag_handler.call("posts/create.rs", "create_post", 4).should eq(["Protected by Rust User request guard"])
  end

  it "leaves an Option-wrapped extractor anonymous" do
    tag_handler.call("posts/read.rs", "get_post", 4).should be_empty
  end

  it "does not count an extractor whose error variant answers 400" do
    tag_handler.call("items/handlers.rs", "list", 4).should be_empty
  end

  # `AppError::NotLoggedIn\n| AppError::NotAdmin => …UNAUTHORIZED`
  it "reads every variant of a multi-line `|` arm, returned through `.ok_or(...)`" do
    tag_handler.call("guarded.rs", "admin", 4).should eq(["Protected by Rust Admin request guard"])
  end

  # `Self::Banned => { StatusCode::FORBIDDEN }` + `Err(Banned)` after `use AppError::*`
  it "reads a block arm on `Self::` and a glob-imported bare variant" do
    tag_handler.call("guarded.rs", "member", 8).should eq(["Protected by Rust Member request guard"])
  end

  it "ignores a 401 variant that is bound to a `let` and never returned" do
    tag_handler.call("guarded.rs", "maybe", 12).should be_empty
  end

  it "ignores a 401 variant that only appears in a match pattern" do
    tag_handler.call("guarded.rs", "anon", 16).should be_empty
  end
end
