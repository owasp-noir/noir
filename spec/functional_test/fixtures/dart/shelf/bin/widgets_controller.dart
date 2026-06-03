import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

// Imperative router built inside a class getter. It is reached from the
// outside as `WidgetsController().router`, so when the parent mounts it
// with `mount('/widgets/', WidgetsController().router)` the routes must
// pick up the `/widgets` prefix (keyed by the class, not the local
// `r` variable).
class WidgetsController {
  Router get router {
    final r = Router()
      ..get('/list', _list)
      ..get('/<id>', _show);
    return r;
  }

  Response _list(Request request) => Response.ok('[]');
  Response _show(Request request, String id) => Response.ok(id);
}
