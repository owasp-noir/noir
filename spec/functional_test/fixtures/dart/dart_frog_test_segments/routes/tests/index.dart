import 'package:dart_frog/dart_frog.dart';

// A quiz backend: the directory name is the URL segment (`/tests`).
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  return Response.json(body: {'tests': []});
}
