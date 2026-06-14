import 'package:angel3_framework/angel3_framework.dart';
import 'package:angel3_framework/http.dart';
import 'package:http/http.dart' as http;

import 'api_routes.dart';

void main() async {
  var app = Angel();

  // Inline lambda — callees from the body.
  app.get('/users', (req, res) async {
    final users = await userService.findAll();
    return res.json(users);
  });

  // Bare function reference handler — recorded as the single callee.
  app.post('/users', createUser);

  // Express-style `:id` path capture → `{id}`.
  app.get('/users/:id', (req, res) => getUser(req));

  // Optional capture `:slug?` drops the `?`.
  app.get('/posts/:slug?', (req, res) => getPost(req));

  // `.all` registers the handler against every verb.
  app.all('/health', (req, res) => healthCheck());

  // Grouped routes compose the prefix; `chain([...])` middleware before
  // the group is ignored for the URL. Groups nest.
  app.chain([authMiddleware]).group('/api', (router) {
    router.get('/version', (req, res) => 'v1');

    router.group('/v2', (inner) {
      inner.post('/widgets', createWidget);
    });
  });

  // Not a route: the `package:http` client's `get` must not be emitted
  // (only `Angel`-bound receivers are routes).
  await http.get(Uri.parse('https://example.com'));

  configureApiRoutes(app);

  var server = AngelHttp(app);
  await server.startServer('127.0.0.1', 3000);
}
