import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'api.dart';
import 'widgets_controller.dart';
import 'tasks_controller.dart';

final router = Router()
  ..get('/users', _listUsers)
  ..post('/users', _createUser)
  ..get('/users/<id>', _getUser)
  ..put('/users/<id>', _updateUser)
  ..delete('/users/<id>', _deleteUser)
  ..all('/echo', _echo)
  ..mount('/api/v1/', apiRouter.call)
  // Class-getter routers mounted under a prefix. Routes must resolve
  // against the controller class, not the inner local variable.
  ..mount('/widgets/', WidgetsController().router)
  ..mount('/tasks/', TasksController().router);

Response _listUsers(Request request) => Response.ok('[]');
Response _createUser(Request request) => Response.ok('{}');
Response _getUser(Request request, String id) => Response.ok(id);
Response _updateUser(Request request, String id) => Response.ok(id);
Response _deleteUser(Request request, String id) => Response.ok(id);
Response _echo(Request request) => Response.ok('echo');
