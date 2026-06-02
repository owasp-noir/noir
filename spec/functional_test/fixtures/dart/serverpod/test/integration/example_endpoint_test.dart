import 'package:serverpod_test/serverpod_test.dart';
import 'package:test/test.dart';

// Integration tests exercise endpoints but are not themselves a server
// surface. They define `Session`-first helpers that must be ignored.
void main() {
  group('ExampleEndpoint', () {
    test('hello returns greeting', () async {
      Future<String> hello(Session session, String name) async => 'Hello $name';
      expect(await hello(session, 'x'), equals('Hello x'));
    });
  });
}
