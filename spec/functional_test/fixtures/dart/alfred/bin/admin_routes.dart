import 'package:alfred/alfred.dart';

// Nested routes via `app.route('/base')..verb('sub', handler)`. The
// `Alfred` instance arrives as a constructor field (so this file imports a
// barrel that re-exports `package:alfred/`, not the package directly), and
// the base path composes with each cascade sub-path the way Alfred's
// `NestedRoute._composePath` does.
class AdminRoutes {
  AdminRoutes(this.app);

  final Alfred app;

  void initialize() {
    app.route('/admin/')
      ..get('', dashboard)
      ..post('users', createAdminUser)
      ..delete('users/:id', deleteAdminUser)
      ..all('*', (req, res) => 'not found');
  }
}
