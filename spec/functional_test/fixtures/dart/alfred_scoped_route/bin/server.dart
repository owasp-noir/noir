import 'package:alfred/alfred.dart';

void userRoutes(Alfred app) {
  final r = app.route('/users');
  r.get('/list', (req, res) => 'users');
  r.post('/create', (req, res) => 'created');
  r.delete('/:id', (req, res) => 'deleted');
}

void postRoutes(Alfred app) {
  final r = app.route('/posts');
  r.get('/list', (req, res) => 'posts');
  r.delete('/:id', (req, res) => 'deleted');
}

void main() async {
  final app = Alfred();
  userRoutes(app);
  postRoutes(app);
  await app.listen();
}
