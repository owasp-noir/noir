// Path constants referenced by `GetPage(name: ...)`. In a real app these
// frequently live in a separate file (often a `part`), so the analyzer
// collects path constants project-wide and resolves them by name.
class Routes {
  static const HOME = '/';
  static const USER = '/user/:id';
  static const UPLOAD = '/upload';
  static const SOCKET = '/socket';
}
