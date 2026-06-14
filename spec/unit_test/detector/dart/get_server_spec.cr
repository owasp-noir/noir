require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect GetServer" do
  options = create_test_options
  instance = Detector::Dart::GetServer.new options

  it "pubspec_with_get_server" do
    content = <<-YAML
      name: example
      dependencies:
        get_server: ^0.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_without_get_server" do
    content = <<-YAML
      name: example
      dependencies:
        shelf: ^1.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_false
  end

  it "import_get_server" do
    content = <<-DART
      import 'package:get_server/get_server.dart';

      void main() {
        runApp(GetServer(getPages: []));
      }
      DART
    instance.detect("lib/main.dart", content).should be_true
  end

  it "non_dart_file" do
    instance.detect("project/notes.txt", "package:get_server/get_server.dart").should be_false
  end

  it "dart_file_without_get_server" do
    instance.detect("lib/util.dart", "void main() {}").should be_false
  end
end
