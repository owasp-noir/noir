require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/utils/http_symbols"
require "../../../src/analyzer/analyzers/dart/shelf"
require "../../../src/analyzer/analyzers/dart/dart_frog"

private def scan_dart(files : Hash(String, String), callees : Bool = false, analyzer : Analyzer.class = Analyzer::Dart::Shelf) : Tuple(Array(Endpoint), Time::Span)
  temp_dir = File.tempname("dart_analyzers")
  CodeLocator.instance.clear_all
  files.each do |relative, content|
    path = File.join(temp_dir, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  options["include_callee"] = YAML::Any.new(true) if callees
  endpoints = [] of Endpoint
  elapsed = Time.measure { endpoints = analyzer.new(options).analyze }
  {endpoints, elapsed}
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe Analyzer::Dart::Shelf do
  # Every route used to pay O(offset) char<->byte seeks (`String#[]`,
  # `MatchData#end`, `char_index_to_byte_index`) once the file held one
  # multi-byte char, so a many-route non-ASCII file was quadratic.
  it "scans a many-route non-ASCII file about as fast as an ASCII one" do
    build = ->(comment : String) do
      String.build do |io|
        io << "import 'package:shelf_router/shelf_router.dart';\nfinal r = Router()\n"
        3000.times { |i| io << "  // #{comment}\n  ..get('/p#{i}/<id>', (req, id) => Response.ok('#{comment}'))\n" }
        io << ";\n"
      end
    end

    ascii, ascii_time = scan_dart({"bin/server.dart" => build.call("plain ascii route comment text")})
    cjk, cjk_time = scan_dart({"bin/server.dart" => build.call("한국어 주석 라우트 설명입니다 ✓ 日本語")})

    ascii.size.should eq(3000)
    cjk.map(&.url).should eq(ascii.map(&.url))
    cjk_time.should be < ascii_time * 4 + 1.second
  end

  # An arrow handler's body ran to the next `;`, which in a `..get(...)`
  # cascade is the end of the whole chain: every route rescanned the rest.
  it "bounds a cascade arrow handler's callee body at its route call" do
    source = String.build do |io|
      io << "import 'package:shelf_router/shelf_router.dart';\nfinal r = Router()\n"
      1000.times { |i| io << "  ..get('/p#{i}', (req) => Response.ok(render#{i}()))\n" }
      io << ";\n"
    end

    plain, plain_time = scan_dart({"bin/server.dart" => source})
    with_callees, callee_time = scan_dart({"bin/server.dart" => source}, callees: true)

    with_callees.map(&.url).should eq(plain.map(&.url))
    with_callees.find! { |e| e.url == "/p0" }.callees.map(&.name).sort!.should eq(["Response.ok", "render0"])
    callee_time.should be < plain_time * 4 + 1.second
  end

  it "reads query, header and body inputs from inline and referenced handlers" do
    source = <<-DART
      import 'package:shelf_router/shelf_router.dart';

      final _router = Router()
        ..get('/echo/<message>', _echoHandler)
        ..post('/messages', (Request request) async {
          final payload = jsonDecode(await request.readAsString());
          return Response.ok(payload['text']);
        })
        ..put('/raw', (Request request) async => Response.ok(await request.readAsString()));

      Response _echoHandler(Request request) {
        // request.headers['commented-out']
        final lang = request.url.queryParameters['lang'];
        final token = request.headers['x-api-key'];
        return Response.ok('$lang $token');
      }
      DART
    endpoints, _ = scan_dart({"bin/server.dart" => source})
    params = ->(url : String) { endpoints.find! { |e| e.url == url }.params.map { |p| {p.name, p.param_type} } }

    params.call("/echo/{message}").should eq([{"message", "path"}, {"lang", "query"}, {"x-api-key", "header"}])
    params.call("/messages").should eq([{"text", "json"}])
    params.call("/raw").should eq([{"body", "json"}])
  end
end

describe Analyzer::Dart::DartFrog do
  it "reads query, header and body inputs from the onRequest file" do
    source = <<-DART
      import 'package:dart_frog/dart_frog.dart';

      Future<Response> onRequest(RequestContext context) async {
        return switch (context.request.method) {
          HttpMethod.get => _get(context),
          HttpMethod.post => _post(context),
          _ => Future.value(Response(statusCode: 405)),
        };
      }

      Future<Response> _get(RequestContext context) async {
        final params = context.request.uri.queryParameters;
        final auth = context.request.headers['Authorization'];
        return Response.json(body: {'limit': params['limit']});
      }

      Future<Response> _post(RequestContext context) async {
        final body = await context.request.json() as Map<String, dynamic>;
        return Response.json(body: {'name': body['name']});
      }
      DART
    endpoints, _ = scan_dart({"routes/users/index.dart" => source}, analyzer: Analyzer::Dart::DartFrog)
    params = ->(verb : String) { endpoints.find! { |e| e.method == verb }.params.map { |p| {p.name, p.param_type} } }

    params.call("GET").should eq([{"Authorization", "header"}, {"limit", "query"}])
    params.call("POST").should eq([{"Authorization", "header"}, {"limit", "query"}, {"name", "json"}])
  end
end
