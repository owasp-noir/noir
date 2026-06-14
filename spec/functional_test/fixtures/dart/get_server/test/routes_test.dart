import 'package:get_server/get_server.dart';

// A `test/` file spins up routes for assertions but never serves
// production traffic — the analyzer must skip it.
void main() {
  final pages = [
    GetPage(name: '/test-only', page: () => Object(), method: Method.get),
  ];
  print(pages);
}
