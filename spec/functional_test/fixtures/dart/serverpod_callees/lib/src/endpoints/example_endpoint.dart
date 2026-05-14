import 'package:serverpod/serverpod.dart';
// Long comment before endpoint classes keeps source offsets honest when comments are stripped.

class ExampleEndpoint extends Endpoint {
  Future<String> hello(Session session, String name) async {
    final user = await UserService.find(name);
    final normalized = _normalize(user);
    return GreetingBuilder.build(normalized);
  }

  Future<bool> ping(Session session) async => Health.check();

  Future<String> _normalize(Session session, String value) async {
    return value.trim();
  }
}

class OrderEndpoint extends Endpoint {
  Future<OrderDto> create(Session session, {required Order order}) async {
    final saved = await session.db.insertRow(order);
    AuditLog.write('order.create', saved);
    return OrderDto.fromModel(saved);
  }
}

class ChatEndpoint extends StreamingEndpoint {
  Future<void> subscribe(Session session, String channel) async {
    await Streams.open(channel);
  }
}

class Order {}
class OrderDto {
  static OrderDto fromModel(Order order) => OrderDto();
}
