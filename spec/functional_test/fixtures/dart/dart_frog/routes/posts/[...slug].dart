import 'package:dart_frog/dart_frog.dart';

// Catch-all route: matches /posts/a, /posts/a/b, /posts/a/b/c, etc.
Response onRequest(RequestContext context, String slug) {
  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: {'slug': slug});
    default:
      return Response(statusCode: 405);
  }
}
