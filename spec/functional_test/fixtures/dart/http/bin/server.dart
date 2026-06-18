import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);

  await for (final HttpRequest request in server) {
    if (request.method == 'GET' && request.uri.path == '/health') {
      final name = request.uri.queryParameters['name'];
      final traceId = request.headers.value('X-Trace-Id');
      final session = request.cookies.firstWhere((cookie) => cookie.name == 'session');
      _writeText(request, 'healthy $name $traceId ${session.value}');
    } else if (request.uri.path == '/users' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      _writeText(request, body);
    } else if (request.method == 'PATCH') {
      if (request.uri.path == '/profiles') {
        final mode = request.headers['X-Profile-Mode'];
        _writeText(request, 'profile $mode');
      }
    }

    if (request.uri.path.startsWith('/files/')) {
      _writeText(request, 'file');
    }

    if (request.uri.path == '/reports') {
      if (request.method == 'DELETE') {
        _writeText(request, 'deleted');
      }
    }

    if (request.method == 'POST') {
      final uploadBody = await utf8.decoder.bind(request).join();
      if (request.uri.path == '/uploads') {
        _writeText(request, uploadBody);
      }
    }

    switch (request.method) {
      case 'PUT':
        if (request.uri.path == '/switch-users') {
          _writeText(request, 'updated');
        }
        break;
    }

    switch (request.uri.path) {
      case '/status':
        _writeText(request, 'ok');
        break;
    }
  }
}

void _writeText(HttpRequest request, String body) {
  request.response
    ..headers.contentType = ContentType.text
    ..write(body);
}
