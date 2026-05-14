require "../../spec_helper"
require "../../../src/miniparsers/dart_callee_extractor"

describe Noir::DartCalleeExtractor do
  it "extracts Dart receiver, static, null-aware, and bare calls" do
    body = <<-DART
      final service = context.read<UserService>();
      final user = await service.find(id);
      repo?.cache(user);
      repo!.save(UserDto.fromJson(user));
      final payload = request.json<Map<String, dynamic>>();
      return Response.json(body: serialize(user));
      DART

    callees = Noir::DartCalleeExtractor.callees_for_body(body, "route.dart", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"context.read", 10},
      {"service.find", 11},
      {"repo?.cache", 12},
      {"repo!.save", 13},
      {"UserDto.fromJson", 13},
      {"request.json", 14},
      {"Response.json", 15},
      {"serialize", 15},
    ])
  end

  it "skips comments, strings, raw strings, triple strings, and reserved words" do
    body = <<-DART
      if (ready()) {
        final text = "Ignored.string()";
        final raw = r"Ignored.raw()";
        final block = '''
          Ignored.triple()
        ''';
        /* Ignored.block(); */
        // Ignored.line();
        assert(true);
        Real.call();
      }
      DART

    callees = Noir::DartCalleeExtractor.callees_for_body(body, "route.dart", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"ready", 20},
      {"Real.call", 29},
    ])
  end

  it "does not report local function declarations as calls" do
    body = <<-DART
      String normalize(String input) => input.trim();
      final value = normalize(name);
      return Response.json(body: value);
      DART

    callees = Noir::DartCalleeExtractor.callees_for_body(body, "route.dart", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"input.trim", 40},
      {"normalize", 41},
      {"Response.json", 42},
    ])
  end

  it "extracts braced and expression bodies" do
    braced = <<-DART
      Response onRequest(RequestContext context) {
        return Response.json(body: Health.status());
      }
      DART

    open_paren = braced.index('(') || -1
    open_paren.should be >= 0
    close_paren = Noir::DartCalleeExtractor.find_matching_delimiter(braced, open_paren, '(', ')')
    close_paren.should_not be_nil
    close_paren.try do |found_close|
      body_info = Noir::DartCalleeExtractor.extract_body_after(braced, found_close + 1)
      body_info.should_not be_nil
      body_info.try do |found_body|
        body, body_start, _ = found_body
        start_line = Noir::DartCalleeExtractor.line_number_for(braced, body_start)
        Noir::DartCalleeExtractor.callees_for_body(body, "route.dart", start_line).map { |name, _, line| {name, line} }.should eq([
          {"Response.json", 2},
          {"Health.status", 2},
        ])
      end
    end

    expression = "Future<String> ping(Session session) async => Health.check();"
    open_paren = expression.index('(') || -1
    open_paren.should be >= 0
    close_paren = Noir::DartCalleeExtractor.find_matching_delimiter(expression, open_paren, '(', ')')
    close_paren.should_not be_nil
    close_paren.try do |found_close|
      body_info = Noir::DartCalleeExtractor.extract_body_after(expression, found_close + 1)
      body_info.should_not be_nil
      body_info.try do |found_body|
        body, body_start, _ = found_body
        start_line = Noir::DartCalleeExtractor.line_number_for(expression, body_start)
        Noir::DartCalleeExtractor.callees_for_body(body, "endpoint.dart", start_line).map { |name, _, line| {name, line} }.should eq([
          {"Health.check", 1},
        ])
      end
    end
  end
end
