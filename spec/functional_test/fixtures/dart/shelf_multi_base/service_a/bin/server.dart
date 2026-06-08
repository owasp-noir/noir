import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final router = Router()
  ..mount('/a', apiRouter.call);

final apiRouter = Router()
  ..get('/shared', _serviceA);

Response _serviceA(Request request) => Response.ok('service-a');
