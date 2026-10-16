import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final app = Router()
  ..get('/in-tests', (Request request) => Response.ok('fake'));
