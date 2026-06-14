import 'package:alfred/alfred.dart';

// Routes registered against an `Alfred`-typed parameter (not a local
// `Alfred()` instantiation). The analyzer binds to the typed parameter so
// these are still discovered.
void configureAuthRoutes(Alfred app) {
  app.post('/auth/login', (req, res) {
    return authService.login(req);
  });

  app.get('/auth/profile', getProfile);
}
