require "../../spec_helper"
require "../../../src/miniparsers/rust_callee_extractor"

describe Noir::RustCalleeExtractor do
  it "extracts path, receiver, and bare calls from Rust handler bodies" do
    body = <<-RUST
      let user = UserService::create(payload).await;
      state.users.find(user.id);
      Json(user)
      RUST

    callees = Noir::RustCalleeExtractor.callees_for_body(body, "main.rs", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService::create", 10},
      {"state.users.find", 11},
      {"Json", 12},
    ])
  end

  it "skips comments, strings, and common Rust noise macros" do
    body = <<-RUST
      // AuditLog::write("ignored")
      let msg = "UserService::create()";
      let _debug = format!("user {}", id);
      println!("done");
      AuditLog::write("created");
      RUST

    callees = Noir::RustCalleeExtractor.callees_for_body(body, "main.rs", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"AuditLog::write", 24},
    ])
  end

  it "keeps namespaced calls whose final segment is a common Rust wrapper" do
    body = <<-RUST
      Ok(user)
      std::format!("user {}", user.id)
      HttpResponse::Ok().json(user)
      HttpResponse::Created().finish()
      RUST

    callees = Noir::RustCalleeExtractor.callees_for_body(body, "main.rs", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"HttpResponse::Ok", 42},
      {"HttpResponse::Created", 43},
    ])
  end

  it "skips block comments across lines" do
    body = <<-RUST
      /*
       * DangerousService::run();
       */
      SafeService::run();
      RUST

    callees = Noir::RustCalleeExtractor.callees_for_body(body, "main.rs", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"SafeService::run", 33},
    ])
  end
end
