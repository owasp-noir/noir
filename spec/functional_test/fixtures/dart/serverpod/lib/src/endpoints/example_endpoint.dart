import 'package:serverpod/serverpod.dart';

class ExampleEndpoint extends Endpoint {
  Future<String> hello(Session session, String name) async {
    return 'Hello $name';
  }

  Future<int> add(Session session, int a, int b) async {
    return a + b;
  }

  // Private helpers should not be exposed.
  Future<void> _internal(Session session) async {}
}

class OrderEndpoint extends Endpoint {
  Future<List<Order>> list(Session session, {required int limit, String? cursor}) async {
    return [];
  }

  Future<Order> create(Session session, Order order) async {
    return order;
  }
}

class HealthEndpoint extends Endpoint {
  Future<bool> ping(Session session) async => true;
}

class Order {}
