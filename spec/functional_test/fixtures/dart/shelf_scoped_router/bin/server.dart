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

void main() {
  final app = Router();
  app.get('/health', _health);
  app.mount('/users', UsersApi().router);
  app.mount('/posts', PostsApi().router);
  app.mount('/admin', AdminApi().router);
}

Response _list(Request request) => Response.ok('list');
Response _get(Request request) => Response.ok('get');
Response _delete(Request request) => Response.ok('delete');
Response _stats(Request request) => Response.ok('stats');
Response _health(Request request) => Response.ok('ok');
