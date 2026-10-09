import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class UsersApi {
  Router get router {
    final router = Router();
    router.get('/', _list);
    router.get('/<id>', _get);
    return router;
  }
}

class PostsApi {
  Router get router {
    final router = Router();
    router.get('/', _list);
    router.delete('/<pid>', _delete);
    return router;
  }
}

// Shares its local name with main()'s `app`.
class AdminApi {
  Router get router {
    final app = Router();
    app.get('/stats', _stats);
    return app;
  }
}

// A mixin body is its own scope, like a class.
mixin ExportRoutes {
  final reports = Router();

  void registerExports() {
    reports.get('/export', _stats);
  }
}

class Server {
  final router = Router();
}

void main() {
  final app = Router();
  app.get('/health', _health);
  app.mount('/users', UsersApi().router);
  app.mount('/posts', PostsApi().router);
  app.mount('/admin', AdminApi().router);

  final reports = Router();
  reports.get('/daily', _stats);
  app.mount('/reports', reports);

  // Another object's `router` field, not a local variable of that name.
  final server = Server();
  server.router.get('/version', _health);
}

Response _list(Request request) => Response.ok('list');
Response _get(Request request) => Response.ok('get');
Response _delete(Request request) => Response.ok('delete');
Response _stats(Request request) => Response.ok('stats');
Response _health(Request request) => Response.ok('ok');
