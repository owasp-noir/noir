require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect Angel3" do
  options = create_test_options
  instance = Detector::Dart::Angel3.new options

  it "pubspec_with_angel3_framework" do
    content = <<-YAML
      name: example
      dependencies:
        angel3_framework: ^8.0.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_without_angel" do
    content = <<-YAML
      name: example
      dependencies:
        shelf: ^1.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_false
  end

  it "import_angel3_framework" do
    content = <<-DART
      import 'package:angel3_framework/angel3_framework.dart';

      void main() async {
        var app = Angel();
        app.get('/', (req, res) => 'hi');
      }
      DART
    instance.detect("bin/server.dart", content).should be_true
  end

  it "import_legacy_angel_framework" do
    content = "import 'package:angel_framework/angel_framework.dart';"
    instance.detect("bin/server.dart", content).should be_true
  end

  it "non_dart_file" do
    instance.detect("project/notes.txt", "package:angel3_framework/angel3_framework.dart").should be_false
  end

  it "dart_file_without_angel" do
    instance.detect("lib/util.dart", "void main() {}").should be_false
  end
end
