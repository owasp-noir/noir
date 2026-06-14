require "../../../spec_helper"
require "../../../../src/detector/detectors/dart/*"

describe "Detect Alfred" do
  options = create_test_options
  instance = Detector::Dart::Alfred.new options

  it "pubspec_with_alfred" do
    content = <<-YAML
      name: example
      dependencies:
        alfred: ^1.1.0
      YAML
    instance.detect("pubspec.yaml", content).should be_true
  end

  it "pubspec_without_alfred" do
    content = <<-YAML
      name: example
      dependencies:
        shelf: ^1.4.0
      YAML
    instance.detect("pubspec.yaml", content).should be_false
  end

  it "import_alfred" do
    content = <<-DART
      import 'package:alfred/alfred.dart';

      void main() {
        final app = Alfred();
        app.get('/', (req, res) => 'hi');
      }
      DART
    instance.detect("bin/server.dart", content).should be_true
  end

  it "non_dart_file" do
    instance.detect("project/notes.txt", "package:alfred/alfred.dart").should be_false
  end

  it "dart_file_without_alfred" do
    instance.detect("lib/util.dart", "void main() {}").should be_false
  end
end
