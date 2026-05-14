import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) =>
    Response.json(body: HealthService.status());
