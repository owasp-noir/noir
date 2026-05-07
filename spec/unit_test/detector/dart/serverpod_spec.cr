require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect Dart Serverpod" do
  options = create_test_options
  instance = Detector::Dart::Serverpod.new options

  it "pubspec_with_serverpod" do
    content = <<-YAML
      name: example
      dependencies:
        serverpod: ^2.0.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_with_serverpod_server" do
    content = <<-YAML
      name: example
      dependencies:
        serverpod_server: ^2.0.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_without_serverpod" do
    content = <<-YAML
      name: example
      dependencies:
        shelf: ^1.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_false
  end

  it "import_serverpod" do
    content = <<-DART
      import 'package:serverpod/serverpod.dart';

      class ExampleEndpoint extends Endpoint {}
      DART
    instance.detect("project/lib/src/endpoints/example.dart", content).should be_true
  end

  it "endpoint_class_extends" do
    content = "class ExampleEndpoint extends Endpoint { }"
    instance.detect("project/lib/src/endpoints/example.dart", content).should be_true
  end

  it "streaming_endpoint_class" do
    content = "class ChatEndpoint extends StreamingEndpoint { }"
    instance.detect("project/lib/src/endpoints/chat.dart", content).should be_true
  end

  it "non_dart_file" do
    instance.detect("project/lib/src/endpoints/example.txt", "package:serverpod/serverpod.dart").should be_false
  end

  it "unrelated_dart_file" do
    instance.detect("project/lib/util.dart", "void main() {}").should be_false
  end
end
