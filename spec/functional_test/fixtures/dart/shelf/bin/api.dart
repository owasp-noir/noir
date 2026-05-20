import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final apiRouter = Router()
  ..get('/status', _status)
  ..get('/items/<itemId|[0-9]+>', _getItem);

// Direct method-call style is also supported.
void registerExtras() {
  apiRouter.patch('/items/<itemId>', _patchItem);
}

Response _status(Request request) => Response.ok('ok');
Response _getItem(Request request, String itemId) => Response.ok(itemId);
Response _patchItem(Request request, String itemId) => Response.ok(itemId);
