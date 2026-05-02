import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context, String id) {
  if (context.request.method == HttpMethod.get) {
    return Response.json(body: <Map<String, Object?>>[]);
  }
  return Response(statusCode: 405);
}
