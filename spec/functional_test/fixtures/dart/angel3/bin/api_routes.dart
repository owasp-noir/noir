import 'package:angel3_framework/angel3_framework.dart';

// Routes registered against an `Angel`-typed parameter (not a local
// `Angel()` instantiation) are still discovered.
void configureApiRoutes(Angel app) {
  app.get('/status', (req, res) => statusService.check());
}
