import 'dart:async';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: <String>[]);
    case HttpMethod.post:
      return Response.json(body: {'id': 1}, statusCode: 201);
    default:
      return Response(statusCode: 405);
  }
}
