require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/utils/http_symbols"
require "../../../src/analyzer/analyzers/dart/shelf"

private def scan_shelf(files : Hash(String, String)) : Tuple(Array(Endpoint), Time::Span)
  temp_dir = File.tempname("dart_shelf")
  CodeLocator.instance.clear_all
  files.each do |relative, content|
    path = File.join(temp_dir, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  endpoints = [] of Endpoint
  elapsed = Time.measure { endpoints = Analyzer::Dart::Shelf.new(options).analyze }
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

    ascii, ascii_time = scan_shelf({"bin/server.dart" => build.call("plain ascii route comment text")})
    cjk, cjk_time = scan_shelf({"bin/server.dart" => build.call("한국어 주석 라우트 설명입니다 ✓ 日本語")})

    ascii.size.should eq(3000)
    cjk.map(&.url).should eq(ascii.map(&.url))
    cjk_time.should be < ascii_time * 4 + 1.second
  end
end
