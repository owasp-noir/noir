require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# The endpoints `RustAuthTagger` tags when each URL is registered by the actix
# app built in the first file (the tmp dir is removed; tags keep their text).
private def actix_tagged(files : Hash(String, String), urls : Array(String)) : Array(Endpoint)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("actix_app_wrap")
  files.each do |rel, src|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, src)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  main = File.join(tmpdir, files.keys.first)
  endpoints = urls.map { |url| Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(main, 1)).tap(&.technology=("rust_actix_web"))) }
  RustAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.reject(&.tags.empty?)
end

# `{url => auth description}` of the guarded endpoints.
private def actix_guards(files : Hash(String, String), urls : Array(String)) : Hash(String, String)
  actix_tagged(files, urls).to_h { |endpoint| {endpoint.url, endpoint.tags.first.description} }
end

APP_WRAP_MIDDLEWARE = <<-RUST
  pub struct AuthTransform {
      keys: Keys,
  }

  impl Service<ServiceRequest> for AuthMiddleware {
      fn call(&self, req: ServiceRequest) -> Self::Future {
          if bad(&req) {
              return Box::pin(async move { Ok(req.into_response(HttpResponse::Unauthorized().body("no"))) });
          }
          self.service.call(req)
      }
  }
  RUST

APP_WRAP_SERVER = <<-RUST
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
      })
  }
  RUST

describe "RustAuthTagger app-wide actix .wrap" do
  urls = ["/", "/healthz", "/readyz", "/readyz/x", "/collections", "/collections/{name}"]

  it "guards every route but the middleware's own whitelist, and says a setting can open it" do
    guards = actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls)
    guards.keys.sort!.should eq ["/collections", "/collections/{name}"]
    guards["/collections"].should contain("AuthTransform")
    guards["/collections"].should contain("only when auth keys are configured")
  end

  it "points the guard at the .wrap line" do
    tag = actix_tagged({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls).first.tags.first
    tag.path.try(&.ends_with?("src/main.rs")).should be_true
    tag.line.should eq 6
  end

  it "does not guard on a middleware whose definition never refuses" do
    logging_only = APP_WRAP_MIDDLEWARE.gsub("HttpResponse::Unauthorized()", "HttpResponse::Ok()")
    actix_guards({"src/main.rs" => APP_WRAP_SERVER, "src/auth.rs" => logging_only}, urls).should be_empty
  end

  it "does not guard on a wrap that is not an auth type" do
    plain = APP_WRAP_SERVER.gsub("AuthTransform", "Compress")
    actix_guards({"src/main.rs" => plain, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls).should be_empty
  end

  it "does not let a test app's wrap guard the real routes" do
    actix_guards({"src/main.rs" => "fn serve() { App::new().service(index) }", "tests/api.rs" => APP_WRAP_SERVER, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls).should be_empty

    in_test_module = "fn serve() { App::new().service(index) }\n#[cfg(test)]\nmod tests {\n#{APP_WRAP_SERVER}\n}\n"
    actix_guards({"src/main.rs" => in_test_module, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls).should be_empty
  end

  it "keeps a scope's wrap on that scope" do
    scoped = <<-RUST
      fn serve() {
          App::new()
              .service(web::scope("/admin").wrap(AuthTransform::new(keys)).service(users))
              .service(index)
      }
      RUST
    guards = actix_guards({"src/main.rs" => scoped, "src/auth.rs" => APP_WRAP_MIDDLEWARE}, ["/admin/users", "/collections"])
    guards.keys.should eq ["/admin/users"]
  end

  it "says so when the whitelist could not be read, rather than guard silently" do
    unread = APP_WRAP_SERVER.gsub(/let mut open = .*\n.*\n/, "")
    guards = actix_guards({"src/main.rs" => unread.gsub("open", "whitelist"), "src/auth.rs" => APP_WRAP_MIDDLEWARE}, urls)
    guards["/healthz"].should contain("whitelisted paths could not be read")
  end
end
