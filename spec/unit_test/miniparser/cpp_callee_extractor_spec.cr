require "../../spec_helper"
require "../../../src/miniparsers/cpp_callee_extractor"

describe Noir::CppCalleeExtractor do
  it "extracts scoped, member, and bare C++ calls from handler bodies" do
    body = <<-CPP
      auto user = UserService::load(id);
      auto token = req->getParameter("token");
      audit.write(user);
      callback(makeResponse(user));
      auto payload = Parser::decode<std::map<std::string, std::vector<int>>>(req->body());
      CPP

    callees = Noir::CppCalleeExtractor.callees_for_body(body, "handler.cpp", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService::load", 10},
      {"req->getParameter", 11},
      {"audit.write", 12},
      {"callback", 13},
      {"makeResponse", 13},
      {"Parser::decode", 14},
      {"req->body", 14},
    ])
  end

  it "skips control keywords, comments, strings, and char literals" do
    body = <<-CPP
      if (ready()) {
        auto text = "Ignored::string() { }";
        char brace = '}';
        /* Ignored::block(); */
        // Ignored::line();
        auto casted = const_cast<User*>(user);
        Real::call();
      }
      CPP

    callees = Noir::CppCalleeExtractor.callees_for_body(body, "handler.cpp", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"ready", 20},
      {"Real::call", 26},
    ])
  end

  it "extracts blocks while ignoring braces in comments and strings" do
    source = <<-CPP
      app.route([] {
        auto text = "}";
        /* } */
        Result::send();
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      callees = Noir::CppCalleeExtractor.callees_for_body(body, "handler.cpp", start_line)
      callees.map { |name, _, line| {name, line} }.should eq([
        {"Result::send", 4},
      ])
    end
  end

  it "does not extract a later block as a lambda body after a named handler route" do
    source = <<-CPP
      CROW_ROUTE(app, "/named")(&show_user);

      auto unrelated = [] {
        Wrong::call();
      };
      CPP

    block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, 0)
    block.should be_nil
  end

  it "does not let a raw string literal close the enclosing block" do
    source = <<-CPP
      CROW_ROUTE(app, "/alpha")
      ([](const crow::request& req) {
          auto body = std::string(R"(it says " and })");
          alphaHelper(body);
          return crow::response(200);
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", start_line).map(&.[0]).should eq([
        "std::string",
        "alphaHelper",
        "crow::response",
      ])
    end
  end

  it "terminates a delimited raw string only on its own )delim sequence" do
    source = <<-CPP
      CROW_ROUTE(app, "/xyz")
      ([](const crow::request& req) {
          auto body = R"xyz(nested )" still inside } here)xyz";
          xyzHelper(body);
          return crow::response(200);
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", start_line).map(&.[0]).should eq([
        "xyzHelper",
        "crow::response",
      ])
    end
  end

  it "handles a multi-line raw string body without emitting phantom callees" do
    body = <<-CPP
      auto doc = R"json({
        "ghost": Ghost::call(),
        "brace": "}"
      })json";
      realHelper(doc);
      CPP

    Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", 1).map(&.[0]).should eq([
      "realHelper",
    ])
  end

  it "keeps encoding-prefixed raw strings and plain strings apart" do
    source = <<-CPP
      handler([] {
          auto wide = LR"(a } b)";
          auto utf8 = u8R"(c } d)";
          Kept::call();
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", start_line).map(&.[0]).should eq([
        "Kept::call",
      ])
    end
  end

  it "degrades an unterminated raw string to the end of the source" do
    source = <<-CPP
      handler([] {
          auto broken = R"(never closed } "
          Lost::call();
      });
      CPP

    Noir::CppCalleeExtractor.extract_block_after(source, 0).should be_nil
    Noir::CppCalleeExtractor.callees_for_body(source, "app.cpp", 1).map(&.[0]).should eq([
      "handler",
    ])
  end

  it "treats a C++14 decimal digit separator as part of the number" do
    source = <<-CPP
      CROW_ROUTE(app, "/beta")
      ([](const crow::request& req) {
          int limit = 1'000;
          betaHelper(limit);
          return crow::response(200);
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", start_line).map(&.[0]).should eq([
        "betaHelper",
        "crow::response",
      ])
    end
  end

  it "treats a hex digit separator as part of the number" do
    source = <<-CPP
      CROW_ROUTE(app, "/gamma")
      ([](const crow::request& req) {
          unsigned mask = 0x1'F;
          gammaHelper(mask);
          return crow::response(200);
      });
      CPP

    block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, 0)
    block.should_not be_nil
    block.try do |found_block|
      body, start_line = found_block
      Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", start_line).map(&.[0]).should eq([
        "gammaHelper",
        "crow::response",
      ])
    end
  end

  it "still lexes char literals that follow an encoding prefix" do
    body = <<-CPP
      char sep = L'}';
      char16_t u = u'}';
      Real::call();
      CPP

    Noir::CppCalleeExtractor.callees_for_body(body, "app.cpp", 1).map(&.[0]).should eq([
      "Real::call",
    ])
  end

  it "strips comments without desynchronizing on raw strings or digit separators" do
    source = <<-CPP
      auto a = R"(// not a comment )";
      int n = 1'000; // dropped
      Kept::call();
      CPP

    stripped = Noir::CppCalleeExtractor.strip_comments(source)
    stripped.bytesize.should eq(source.bytesize)
    stripped.includes?("// not a comment").should be_true
    stripped.includes?("dropped").should be_false
    stripped.includes?("Kept::call").should be_true
  end
end
