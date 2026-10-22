import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// A test server for the package.
final app = Router()
  ..get('/in-testing', (Request request) => Response.ok('fake'));
