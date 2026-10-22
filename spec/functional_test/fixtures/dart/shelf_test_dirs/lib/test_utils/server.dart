import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final app = Router()
  ..get('/in-test-utils', (Request request) => Response.ok('fake'));
