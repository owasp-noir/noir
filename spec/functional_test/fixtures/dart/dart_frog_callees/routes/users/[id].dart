import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final service = context.read<UserService>();
  switch (context.request.method) {
    case HttpMethod.get:
      final user = await service.find(id);
      AuditLog.write('show', user);
      return Response.json(body: serializeUser(user));
    case HttpMethod.put:
      final body = await context.request.json<Map<String, dynamic>>();
      final updated = await service.save(id, UserDto.fromJson(body));
      return Response.json(body: renderUser(updated));
    default:
      return Response(statusCode: 405);
  }
}
