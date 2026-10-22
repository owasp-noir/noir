import 'package:dart_frog/dart_frog.dart';

// Dart Frog's own mirror tree, never served.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  return Response.json(body: {'mock': true});
}
