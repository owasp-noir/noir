import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';

// A WebSocket route: the handler upgrades the request, so it serves only a
// GET (the upgrade handshake) and must not fan out to the fall-back verb
// set. The endpoint's protocol is reported as `ws`.
Future<Response> onRequest(RequestContext context) async {
  final handler = webSocketHandler((channel, protocol) {
    channel.stream.listen((event) {
      channel.sink.add(event);
    });
  });
  return handler(context);
}
