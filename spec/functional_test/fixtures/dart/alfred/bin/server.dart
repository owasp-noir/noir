import 'package:alfred/alfred.dart';

import 'users_controller.dart';
import 'auth_routes.dart';

void main() async {
  final app = Alfred();

  // Inline lambda handler — callees are extracted from the body.
  app.get('/users', (req, res) async {
    final users = await userService.findAll();
    return res.json(users);
  });

  // Bare function reference handler — recorded as the single callee.
  app.post('/users', createUser);

  // Typed path param `:id:int` collapses to `{id}`.
  app.get('/users/:id:int', (req, res) {
    return getUser(req.params['id']);
  });

  // `delete` with a trailing `middleware:` argument after the handler.
  app.delete('/users/:id', (req, res) {
    return deleteUser(req.params['id']);
  }, middleware: [authMiddleware]);

  // `.all` registers the handler against every verb.
  app.all('/health', (req, res) => healthCheck());

  // `.route(...)`/`.use(...)` are not verbs and must not be emitted.
  app.use(loggingMiddleware);

  // Routes registered from another file via a `Alfred`-typed parameter.
  configureAuthRoutes(app);

  await app.listen();
}
