import 'package:dart_frog/dart_frog.dart';

// `onRequest` is dispatched for *every* verb, so unsupported methods are
// commonly enumerated in fall-through `case` clauses that return
// `methodNotAllowed`. Those rejected verbs must NOT be surfaced as
// real endpoints — only GET and PUT below are.
Future<Response> onRequest(RequestContext context, String id) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _show(context, id);
    case HttpMethod.put:
      return _update(context, id);
    case HttpMethod.post:
    case HttpMethod.delete:
    case HttpMethod.patch:
    case HttpMethod.head:
    case HttpMethod.options:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _show(RequestContext context, String id) async {
  return Response.json(body: {'id': id});
}

Future<Response> _update(RequestContext context, String id) async {
  return Response.json(body: {'id': id, 'updated': true});
}
