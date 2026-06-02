import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

part 'tasks_controller.g.dart';

// `shelf_router` code-gen style: handlers are declared with
// `@Route.<verb>('/path')` annotations and wired up by the generated
// `_$TasksControllerRouter`. The parent mounts this at `/tasks/`.
class TasksController {
  @Route.get('/all')
  Future<Response> index(Request request) async {
    final tasks = await _repository.fetchAll();
    return Response.ok(tasks.toString());
  }

  @Route.post('/<id>/done')
  Future<Response> markDone(Request request, String id) async {
    await _repository.complete(id);
    return Response.ok(id);
  }

  final _repository = _TaskRepository();

  Router get router => _$TasksControllerRouter(this);
}

class _TaskRepository {
  Future<List<String>> fetchAll() async => [];
  Future<void> complete(String id) async {}
}
