import 'dart:io';

void main() {
  final fake = '/test-only';
  print('${HttpServer.bind} $fake');
}
