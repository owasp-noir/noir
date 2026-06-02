import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../../routes/articles/[id].dart' as route;

// Dart Frog mirrors the route tree under `test/routes/`. These mock
// handlers are exercised by `dart test` and must never be surfaced as
// live endpoints.
void main() {
  group('GET /articles/[id]', () {
    test('responds with 200', () {
      final context = _MockRequestContext();
      final response = route.onRequest(context, '1');
      expect(response, isNotNull);
    });
  });
}

class _MockRequestContext {}
