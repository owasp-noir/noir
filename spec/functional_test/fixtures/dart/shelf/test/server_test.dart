import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

// `dart test` fixtures often spin up real `Router()` instances. Anything
// under `test/` is not a production surface and must be ignored.
void main() {
  test('routes a request', () {
    final router = Router()..get('/ignored', (Request request) => Response.ok('x'));
    expect(router, isNotNull);
  });
}
