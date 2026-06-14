import 'package:angel3_framework/angel3_framework.dart';

// A test harness spins up a real `Angel()` instance, but `test/` files
// never serve production traffic — the analyzer must skip them.
void main() {
  var app = Angel();
  app.get('/test-only', (req, res) => 'fixture');
}
