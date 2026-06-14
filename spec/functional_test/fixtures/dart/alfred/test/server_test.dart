import 'package:alfred/alfred.dart';

// A test harness spins up a real `Alfred()` instance, but `test/` files
// never serve production traffic — the analyzer must skip them.
void main() {
  final app = Alfred();
  app.get('/test-only', (req, res) => 'fixture');
}
