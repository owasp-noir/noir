require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# `{url => handler}` of the routes the fixtures register.
URLS = {
  "/"                   => "index",
  "/healthz"            => "healthz",
  "/readyz"             => "readyz",
  "/readyz/x"           => "readyz_x",
  "/collections"        => "collections",
  "/collections/{name}" => "collection",
  "/metrics"            => "metrics",
}

# The endpoints `RustAuthTagger` tags when the first file builds the actix app
# (the tmp dir is removed; tags keep their text). `method` is every route's.
private def actix_tagged(files : Hash(String, String), method = "GET") : Array(Endpoint)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("actix_app_wrap")
  files["Cargo.toml"] = "[package]\nname = \"t\"\n" unless files.has_key?("Cargo.toml")
  files.each do |rel, src|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, src)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  main = File.join(tmpdir, files.keys.first)
  endpoints = URLS.map do |url, name|
    endpoint = Endpoint.new(url, method, [] of Param, Details.new(PathInfo.new(main, 1)).tap(&.technology=("rust_actix_web")))
    endpoint.handler = Handler.new(name, main, 1)
    endpoint
  end
  RustAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.reject(&.tags.empty?)
end

# `{url => auth description}` of the guarded endpoints.
private def actix_guards(files : Hash(String, String), method = "GET") : Hash(String, String)
  actix_tagged(files, method).to_h { |endpoint| {endpoint.url, endpoint.tags.first.description} }
end

APP_WRAP_MIDDLEWARE = <<-RUST
  pub struct AuthTransform {
      keys: Keys,
  }

  impl<S> Transform<S, ServiceRequest> for AuthTransform {
      type Transform = AuthMiddleware<S>;
      fn new_transform(&self, service: S) -> Self::Future {
          ready(Ok(AuthMiddleware { service }))
      }
  }

  impl Service<ServiceRequest> for AuthMiddleware {
      fn call(&self, req: ServiceRequest) -> Self::Future {
          if bad_token(&req) {
              return Box::pin(async move { Ok(req.into_response(HttpResponse::Unauthorized().body("no"))) });
          }
          self.service.call(req)
      }
  }
  RUST

APP_WRAP_SERVER = <<-RUST
  fn config(cfg: &mut web::ServiceConfig) {
      cfg.service(healthz).service(readyz).service(readyz_x).service(collections).service(collection);
  }

  fn serve(keys: Option<Keys>) {
      let mut open = vec![WhitelistItem::exact("/"), WhitelistItem::prefix("/readyz")];
      open.push(WhitelistItem::exact("/healthz"));
      HttpServer::new(move || {
          App::new()
              .wrap(ConditionEx::from_option(keys.as_ref().map(
                  |keys| AuthTransform::new(keys.clone(), open.clone()),
              )))
              .wrap(Logger::default())
              .service(index)
              .configure(config)
      })
  }
  RUST

describe "RustAuthTagger app-wide actix .wrap" do
  it "guards the App's routes but the middleware's own whitelist, and says a setting can open it" do
    guards = actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE})
    guards.keys.sort!.should eq ["/collections", "/collections/{name}"]
    guards["/collections"].should contain("AuthTransform")
    guards["/collections"].should contain("only when auth keys are configured")
  end

  it "points the guard at the .wrap line" do
    tag = actix_tagged({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).first.tags.first
    tag.path.try(&.ends_with?("src/main.rs")).should be_true
    tag.line.should eq 10
  end

  it "does not guard a route the App does not register, even in the same crate" do
    # `/metrics` belongs to nobody's chain here.
    guards = actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE})
    guards.has_key?("/metrics").should be_false
  end

  it "keeps two Apps of one file apart, and says when a handler is also served open" do
    second = APP_WRAP_SERVER + "\nfn metrics_server() {\n    HttpServer::new(|| App::new().wrap(Compress::default()).service(metrics).service(collection))\n}\n"
    guards = actix_guards({"src/main.rs" => second, "src/auth.rs" => APP_WRAP_MIDDLEWARE})
    guards.has_key?("/metrics").should be_false
    # Served open by the second App too: a note, not a guard.
    tagged = actix_tagged({"src/main.rs" => second, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).find! { |endpoint| endpoint.url == "/collections/{name}" }
    tagged.tags.map(&.name).should eq ["auth_partial"]
    tagged.tags.first.description.should contain("also served without it by another App")
    guards["/collections"].should_not contain("also served")
  end

  it "does not guard on a middleware whose definition never refuses" do
    logging_only = APP_WRAP_MIDDLEWARE.gsub("HttpResponse::Unauthorized()", "HttpResponse::Ok()")
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => logging_only}).should be_empty
  end

  it "judges the wrapped type's own call, not the file" do
    shared = APP_WRAP_MIDDLEWARE.gsub("fn call", "fn other") + "\nimpl Service<ServiceRequest> for RequireAdmin {\n    fn call(&self, req: ServiceRequest) -> Self::Future {\n        if no_token(&req) { return Box::pin(async { Ok(HttpResponse::Unauthorized().finish()) }); }\n        self.service.call(req)\n    }\n}\n"
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => shared}).should be_empty
  end

  it "does not guard on a logger that only reads the 401 the inner service answered" do
    logger = <<-RUST
      pub struct AuthTransform { }
      impl<S> Transform<S, ServiceRequest> for AuthTransform {
          type Transform = AuthMiddleware<S>;
      }
      impl Service<ServiceRequest> for AuthMiddleware {
          fn call(&self, req: ServiceRequest) -> Self::Future {
              let fut = self.service.call(req);
              Box::pin(async move {
                  let res = fut.await?;
                  match res.status() {
                      StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => log::warn!("token rejected"),
                      _ => {}
                  }
                  Ok(res)
              })
          }
      }
      RUST
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => logger}).should be_empty
  end

  it "reads a method test by what its branch does: a pass-through exempts the verb, a refusal limits to it" do
    passes = ->(verb : String) { APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req) {", "if req.method() == Method::#{verb} {\n return Box::pin(self.service.call(req));\n }\n if bad_token(&req) {") }
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => passes.call("GET")}, "GET").should be_empty
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => passes.call("GET")}, "POST").keys.sort!.should eq ["/collections", "/collections/{name}"]
    # A CORS preflight skip leaves GET and POST guarded.
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => passes.call("OPTIONS")}, "GET").keys.sort!.should eq ["/collections", "/collections/{name}"]
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => passes.call("OPTIONS")}, "OPTIONS").should be_empty

    only_post = APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if req.method() == Method::POST && bad_token(&req)")
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => only_post}, "GET").should be_empty
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => only_post}, "POST").should_not be_empty
  end

  it "keeps same-named handlers of different modules apart" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("actix_app_modules")
    files = {
      "Cargo.toml"    => "[package]\nname = \"t\"\n",
      "src/main.rs"   => "mod admin;\nmod public;\nfn serve() {\n    App::new().wrap(AuthTransform::new(keys)).service(admin::index)\n}\nfn open() {\n    App::new().service(public::index)\n}\n",
      "src/admin.rs"  => "pub fn index() {}\n",
      "src/public.rs" => "pub fn index() {}\n",
      "src/auth.rs"   => APP_WRAP_MIDDLEWARE,
    }
    files.each do |rel, src|
      path = File.join(tmpdir, rel)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, src)
      CodeLocator.instance.register_path(path)
    end
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = {"/admin" => "src/admin.rs", "/" => "src/public.rs"}.map do |url, rel|
      file = File.join(tmpdir, rel)
      endpoint = Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(file, 1)).tap(&.technology=("rust_actix_web")))
      endpoint.handler = Handler.new("index", file, 1)
      endpoint
    end
    RustAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)
    endpoints.find! { |e| e.url == "/admin" }.tags.map(&.name).should eq ["auth"]
    endpoints.find! { |e| e.url == "/" }.tags.should be_empty
  end

  it "sees a unit-struct wrap, and ignores a refusal that only remaps the inner service's error" do
    unit = APP_WRAP_SERVER.gsub(/\.wrap\(ConditionEx.*?\)\)\)/m, ".wrap(auth::AuthTransform)")
    actix_guards({"src/main.rs" => unit, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).keys.should contain("/collections")

    remap = APP_WRAP_MIDDLEWARE[0, APP_WRAP_MIDDLEWARE.index!("impl Service")] + "impl Service<ServiceRequest> for AuthMiddleware {\n    fn call(&self, req: ServiceRequest) -> Self::Future {\n        let token = read_token(&req);\n        let fut = self.service.call(req);\n        Box::pin(async move { match fut.await { Ok(r) => Ok(r), Err(e) => Err(ErrorUnauthorized(e)) } })\n    }\n}\n"
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => remap}).should be_empty
  end

  it "treats a method-conditional refusal as limited to the other verbs" do
    conditional = APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if req.method() != Method::GET && bad_token(&req)")
    files = {"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => conditional}
    actix_guards(files.dup, "GET").should be_empty
    actix_guards(files.dup, "POST").keys.sort!.should eq ["/collections", "/collections/{name}"]
  end

  it "does not guard on a wrap that is not an auth type, or only says 'Auth' in a string" do
    plain = APP_WRAP_SERVER.gsub("AuthTransform::new(keys.clone(), open.clone())", "Compress::default()")
    actix_guards({"src/main.rs" => plain, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).should be_empty
    stringy = APP_WRAP_SERVER.gsub(/\.wrap\(ConditionEx.*?\)\)\)/m, ".wrap(Logger::new(\"%a %{Authorization}i\")).wrap(DefaultHeaders::new().add((\"X-Auth-Version\", \"2\")))")
    actix_guards({"src/main.rs" => stringy, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).should be_empty
  end

  it "does not let a test app's wrap guard the real routes" do
    actix_guards({"src/main.rs" => "fn serve() { App::new().service(collections) }", "tests/api.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).should be_empty

    in_test_module = "fn serve() { App::new().service(collections) }\n#[cfg(test)]\nmod tests {\n#{APP_WRAP_SERVER}\n}\n"
    actix_guards({"src/main.rs" => in_test_module, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).should be_empty
  end

  it "keeps a scope's wrap on that scope" do
    scoped = <<-RUST
      fn serve() {
          App::new()
              .service(web::scope("/admin").wrap(AuthTransform::new(keys)).service(users))
              .service(collections)
      }
      RUST
    actix_guards({"src/main.rs" => scoped, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).should be_empty
  end

  it "reads only the whitelist the wrap uses: no comments, no other fn" do
    commented = APP_WRAP_SERVER.gsub("let mut open = vec![", "// WhitelistItem::prefix(\"/collections\")\n    let mut open = vec![")
    actix_guards({"src/main.rs" => commented, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).has_key?("/collections").should be_true

    other_fn = APP_WRAP_SERVER + "\nfn unrelated() {\n    let mut open = vec![WhitelistItem::prefix(\"/collections\")];\n}\n"
    actix_guards({"src/main.rs" => other_fn, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).has_key?("/collections").should be_true
  end

  it "reads inline literal exclusions, and says so when the whitelist cannot be read" do
    inline = APP_WRAP_SERVER.gsub("AuthTransform::new(keys.clone(), open.clone())", "AuthTransform::new(keys.clone()).skip_paths(vec![\"/collections\"])")
    guards = actix_guards({"src/main.rs" => inline, "src/auth.rs" => APP_WRAP_MIDDLEWARE})
    guards.has_key?("/collections").should be_false
    guards.has_key?("/collections/{name}").should be_true

    unread = APP_WRAP_SERVER.gsub(/let mut open = .*\n.*\n/, "").gsub("open", "whitelist")
    actix_guards({"src/main.rs" => unread, "src/auth.rs" => APP_WRAP_MIDDLEWARE})["/healthz"].should contain("whitelisted paths could not be read")
  end
end
