import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

// The one real route. Every other file in this project is a test server or
// a scaffold template and must not be reported.
final app = Router()
  ..get('/real', _real);

Response _real(Request request) => Response.ok('real');
