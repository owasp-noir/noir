require "../../spec_helper"
require "../../../src/miniparsers/rust_callee_extractor_ts"

describe Noir::RustCalleeExtractorTS do
  describe ".callees_for_body_text" do
    it "matches the legacy regex extractor on path / receiver / bare calls" do
      body = <<-RUST
        let user = UserService::create(payload).await;
        state.users.find(user.id);
        Json(user)
        RUST

      callees = Noir::RustCalleeExtractorTS.callees_for_body_text(body, "main.rs", 10)
      callees.map { |name, _, line| {name, line} }.should eq([
        {"UserService::create", 10},
        {"state.users.find", 11},
        {"Json", 12},
      ])
    end

    it "drops chained-on-call receivers and turbofish wrappers" do
      body = <<-RUST
        let cookie = jar.get("token").unwrap();
        execute::<UserService>(&payload);
        RUST

      callees = Noir::RustCalleeExtractorTS.callees_for_body_text(body, "main.rs", 5).map { |name, _, _| name }
      # `jar.get(...).unwrap()` chains on a call — the outer `unwrap` is
      # dropped; `jar.get` is the only kept receiver-style callee. The
      # turbofish `execute::<…>` peels to `execute`.
      callees.should contain("jar.get")
      callees.should contain("execute")
      callees.should_not contain("unwrap")
    end

    it "keeps namespaced calls whose last segment is a reserved wrapper" do
      body = <<-RUST
        Ok(user)
        std::format!("user {}", user.id)
        HttpResponse::Ok().json(user)
        HttpResponse::Created().finish()
        RUST

      callees = Noir::RustCalleeExtractorTS.callees_for_body_text(body, "main.rs", 40)
      names = callees.map { |name, _, _| name }
      names.should contain("HttpResponse::Ok")
      names.should contain("HttpResponse::Created")
      names.should_not contain("Ok")
      names.should_not contain("std::format!")
    end

    it "captures macro invocations with the trailing bang" do
      body = <<-RUST
        warn!("once");
        log::info!("twice");
        AuditLog::write("created");
        RUST

      callees = Noir::RustCalleeExtractorTS.callees_for_body_text(body, "main.rs", 1).map { |name, _, _| name }
      callees.should contain("warn!")
      callees.should contain("log::info!")
      callees.should contain("AuditLog::write")
    end

    it "handles multi-line call expressions the regex scanner used to miss" do
      body = <<-RUST
        UserService::create(
            payload,
            ctx,
        );
        RUST

      callees = Noir::RustCalleeExtractorTS.callees_for_body_text(body, "main.rs", 1).map { |name, _, line| {name, line} }
      callees.should eq([{"UserService::create", 1}])
    end
  end

  describe ".callees_in_body" do
    it "walks a pre-parsed function body without re-parsing" do
      source = <<-RUST
        fn handler(state: AppState) {
            UserService::list(state);
            state.audit.write("listed");
        }
        RUST

      found = [] of {String, Int32}
      Noir::TreeSitter.parse_rust(source) do |root|
        # The first named child should be the function_item.
        fn_node = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(root) do |c|
          fn_node = c if Noir::TreeSitter.node_type(c) == "function_item"
        end
        fn_node_unwrapped = fn_node.should_not be_nil
        body = Noir::TreeSitter.field(fn_node_unwrapped, "body")
        body_unwrapped = body.should_not be_nil
        Noir::RustCalleeExtractorTS.callees_in_body(body_unwrapped, source, "handler.rs").each do |name, _, line|
          found << {name, line}
        end
      end

      found.should contain({"UserService::list", 2})
      found.should contain({"state.audit.write", 3})
    end
  end
end
