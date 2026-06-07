class SharedRoute extends Route {
  SharedRoute() : super(methods: {Method.get});

  Future<Response> handleCall(Session session) async {
    return Response();
  }
}
