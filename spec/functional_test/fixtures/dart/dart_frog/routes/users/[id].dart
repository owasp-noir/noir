import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context, String id) {
  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: {'id': id});
    case HttpMethod.put:
      return Response.json(body: {'id': id, 'updated': true});
    case HttpMethod.delete:
      return Response(statusCode: 204);
    default:
      return Response(statusCode: 405);
  }
}
