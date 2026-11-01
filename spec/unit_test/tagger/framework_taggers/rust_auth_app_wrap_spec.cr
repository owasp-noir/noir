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
  fn index() {} fn healthz() {} fn readyz() {} fn readyz_x() {} fn collections() {} fn collection() {} fn metrics() {}
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

# Builds a crate from `files`, tags `{url => {handler fn file, line}}` and returns `{url => tag names}`.
private def module_tags(files : Hash(String, String), routes : Hash(String, Tuple(String, Int32))) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("actix_app_modules")
  files["Cargo.toml"] = "[package]\nname = \"t\"\n"
  files.each do |rel, src|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, src)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  endpoints = routes.map do |url, (rel, line)|
    file = File.join(tmpdir, rel)
    endpoint = Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(file, line)).tap(&.technology=("rust_actix_web")))
    endpoint.handler = Handler.new("index", file, line)
    endpoint
  end
  RustAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.to_h { |endpoint| {endpoint.url, endpoint.tags.map(&.name)} }
end

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
    tag.line.should eq 11
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

  it "never opens a route because of a method test: every verb stays guarded, the description says so" do
    all_verbs = ["/collections", "/collections/{name}"]
    note = "may exempt some HTTP methods"
    variants = {
      "pass-through GET"   => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req) {", "if req.method() == Method::GET {\n return Box::pin(self.service.call(req));\n }\n if bad_token(&req) {"),
      "OPTIONS preflight"  => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req) {", "if req.method() == Method::OPTIONS {\n return Box::pin(self.service.call(req));\n }\n if bad_token(&req) {"),
      "!= GET refusal"     => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if req.method() != Method::GET && bad_token(&req)"),
      "== GET and a path"  => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if req.method() == Method::GET && req.path() == \"/health\" && bad_token(&req)"),
      "negated method"     => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if !(req.method() == Method::GET) && bad_token(&req)"),
      "bound read-only"    => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req) {", "let read_only = req.method() == Method::GET;\n if !read_only && bad_token(&req) {"),
      "matches! on method" => APP_WRAP_MIDDLEWARE.gsub("if bad_token(&req)", "if !matches!(req.method(), &Method::GET | &Method::HEAD) && bad_token(&req)"),
    }
    variants.each do |label, middleware|
      ["GET", "POST", "OPTIONS"].each do |verb|
        guards = actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => middleware}, verb)
        guards.keys.sort!.should eq(all_verbs), "#{label} #{verb}"
        guards["/collections"].should contain(note)
      end
    end
    plain = actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE})
    plain["/collections"].should_not contain("HTTP methods")
  end

  it "keeps same-named handlers of different files apart" do
    tags = module_tags({
      "src/main.rs"   => "mod admin;\nmod public;\nfn serve() {\n    App::new().wrap(AuthTransform::new(keys)).service(admin::index)\n}\nfn open() {\n    App::new().service(public::index)\n}\n",
      "src/admin.rs"  => "pub fn index() {}\n",
      "src/public.rs" => "pub fn index() {}\n",
      "src/auth.rs"   => APP_WRAP_MIDDLEWARE,
    }, {"/admin" => {"src/admin.rs", 1}, "/" => {"src/public.rs", 1}})
    tags["/admin"].should eq ["auth"]
    tags["/"].should be_empty
  end

  it "keeps same-named handlers of inline modules of one file apart" do
    tags = module_tags({
      "src/main.rs" => "mod admin { pub fn index() {} }\nmod public { pub fn index() {} }\nfn serve() {\n    App::new().wrap(AuthTransform::new(keys)).service(admin::index)\n}\nfn open() {\n    App::new().service(public::index)\n}\n",
      "src/auth.rs" => APP_WRAP_MIDDLEWARE,
    }, {"/admin" => {"src/main.rs", 1}, "/" => {"src/main.rs", 2}})
    tags["/admin"].should eq ["auth"]
    tags["/"].should be_empty
  end

  it "resolves a bare name through the file's use items, glob imports included" do
    tags = module_tags({
      "src/main.rs"       => "mod admin;\nmod public;\nmod admin_srv;\nmod public_srv;\n",
      "src/admin.rs"      => "pub fn index() {}\n",
      "src/public.rs"     => "pub fn index() {}\n",
      "src/admin_srv.rs"  => "use crate::admin::*;\npub fn run() { App::new().wrap(AuthTransform::new(keys)).service(index); }\n",
      "src/public_srv.rs" => "use crate::public::*;\npub fn run() { App::new().service(index); }\n",
      "src/auth.rs"       => APP_WRAP_MIDDLEWARE,
    }, {"/admin" => {"src/admin.rs", 1}, "/" => {"src/public.rs", 1}})
    tags["/admin"].should eq ["auth"]
    tags["/"].should be_empty
  end

  it "does not lend a guard or a note to a same-named fn when the registered name stays ambiguous" do
    tags = module_tags({
      "src/main.rs"   => "mod auth;\nmod public;\nmacro_rules! handler { ($n:ident) => { async fn $n() {} } }\nhandler!(index);\nfn serve() {\n    App::new().wrap(AuthTransform::new(keys)).route(\"/admin\", web::get().to(index));\n}\nfn open() {\n    App::new().configure(public::routes!());\n}\n",
      "src/public.rs" => "pub fn index() {}\n",
      "src/auth.rs"   => APP_WRAP_MIDDLEWARE,
    }, {"/admin" => {"src/main.rs", 4}, "/public" => {"src/public.rs", 1}})
    tags["/public"].should be_empty
  end

  it "sees a unit-struct wrap, and ignores a refusal that only remaps the inner service's error" do
    unit = APP_WRAP_SERVER.gsub(/\.wrap\(ConditionEx.*?\)\)\)/m, ".wrap(auth::AuthTransform)")
    actix_guards({"src/main.rs" => unit, "src/auth.rs" => APP_WRAP_MIDDLEWARE}).keys.should contain("/collections")

    remap = APP_WRAP_MIDDLEWARE[0, APP_WRAP_MIDDLEWARE.index!("impl Service")] + "impl Service<ServiceRequest> for AuthMiddleware {\n    fn call(&self, req: ServiceRequest) -> Self::Future {\n        let token = read_token(&req);\n        let fut = self.service.call(req);\n        Box::pin(async move { match fut.await { Ok(r) => Ok(r), Err(e) => Err(ErrorUnauthorized(e)) } })\n    }\n}\n"
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => remap}).should be_empty
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
