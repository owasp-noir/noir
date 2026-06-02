import 'dart:convert';

import 'package:serverpod/serverpod.dart';

// `Route` with an explicit `methods: {Method.post}` set — surfaced as a
// single POST endpoint. The `handleCall` body supplies the callees.
class WebhookRoute extends Route {
  WebhookRoute() : super(methods: {Method.post});

  @override
  Future<bool> handleCall(Session session, Request request) async {
    final rawBody = await utf8.decoder.bind(request.body.read()).join();
    final payload = jsonDecode(rawBody) as Map<String, dynamic>;
    await processWebhook(session, payload);
    return true;
  }
}
