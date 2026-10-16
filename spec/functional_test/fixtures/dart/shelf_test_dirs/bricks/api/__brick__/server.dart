import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final app = Router()
  ..get('/in-brick', (Request request) => Response.ok('template'));
