import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final router = Router()
  ..mount('/b', apiRouter.call);

final apiRouter = Router()
  ..post('/shared', _serviceB);

Response _serviceB(Request request) => Response.ok('service-b');
