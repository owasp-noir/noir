require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect Dart Frog" do
  options = create_test_options
  instance = Detector::Dart::DartFrog.new options

  it "pubspec_with_dart_frog" do
    content = <<-YAML
      name: example
      dependencies:
        dart_frog: ^1.0.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_without_dart_frog" do
    content = <<-YAML
      name: example
      dependencies:
        shelf: ^1.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_false
  end

  it "import_dart_frog" do
    content = <<-DART
      import 'package:dart_frog/dart_frog.dart';

      Response onRequest(RequestContext context) => Response(body: 'hi');
      DART
    instance.detect("project/routes/index.dart", content).should be_true
  end

  it "route_with_on_request_handler" do
    content = "Response onRequest(RequestContext context) { return Response(); }"
    instance.detect("project/routes/users.dart", content).should be_true
  end

  it "route_with_future_response_handler" do
    content = "Future<Response> onRequest(RequestContext context) async { return Response(); }"
    instance.detect("project/routes/users.dart", content).should be_true
  end

  it "non_dart_file" do
    instance.detect("project/routes/index.txt", "package:dart_frog/dart_frog.dart").should be_false
  end

  it "dart_file_outside_routes_without_import" do
    instance.detect("project/lib/util.dart", "void main() {}").should be_false
  end
end
