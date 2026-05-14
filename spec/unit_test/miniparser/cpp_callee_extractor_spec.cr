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
end
