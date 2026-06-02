import 'package:serverpod/serverpod.dart';

import 'src/web/routes/root.dart';
import 'src/web/routes/webhook.dart';

void run(List<String> args) async {
  final pod = Serverpod(args, Protocol(), Endpoints());

  // WidgetRoute → GET. Registered at two paths.
  pod.webServer.addRoute(RootRoute(), '/');
  pod.webServer.addRoute(RootRoute(), '/index.html');

  // Route with an explicit POST methods set — a webhook.
  pod.webServer.addRoute(WebhookRoute(), '/webhook');

  // Static file serving is not a handler endpoint and must be skipped.
  pod.webServer.addRoute(RouteStaticDirectory(serverDirectory: 'static', basePath: '/'), '/static/*');

  await pod.start();
}
