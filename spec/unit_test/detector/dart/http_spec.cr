require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect Dart HttpServer" do
  options = create_test_options
  instance = Detector::Dart::Http.new options

  it "detects dart io HttpServer usage" do
    content = <<-DART
      import 'dart:io';

      Future<void> main() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
        await for (final HttpRequest request in server) {
          request.response.write('ok');
        }
      }
      DART
    instance.detect("bin/server.dart", content).should be_true
  end

  it "detects aliased dart io HttpServer usage" do
    content = <<-DART
      import 'dart:io' as io;

      Future<void> main() async {
        final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 8080);
        server.listen((io.HttpRequest request) {});
      }
      DART
    instance.detect("bin/server.dart", content).should be_true
  end

  it "does not detect unrelated dart io usage" do
    content = <<-DART
      import 'dart:io';

      void main() {
        final file = File('README.md');
        print(file.path);
      }
      DART
    instance.detect("bin/tool.dart", content).should be_false
  end

  it "does not detect HttpServer without dart io import" do
    instance.detect("bin/server.dart", "void main() { print('HttpServer'); }").should be_false
  end

  it "does not detect non Dart files" do
    instance.detect("notes.txt", "import 'dart:io'; HttpServer.bind();").should be_false
  end
end
