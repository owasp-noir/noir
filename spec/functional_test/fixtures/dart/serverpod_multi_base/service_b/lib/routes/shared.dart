class SharedRoute extends Route {
  SharedRoute() : super(methods: {Method.post});

  Future<Response> handleCall(Session session) async {
    return Response();
  }
}
