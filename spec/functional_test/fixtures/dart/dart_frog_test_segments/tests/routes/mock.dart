import 'package:dart_frog/dart_frog.dart';

// A tests/ tree above the routes/ mirror is not served.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }
  return Response.json(body: {'mock': true});
}
