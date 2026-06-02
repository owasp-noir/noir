import 'package:dart_frog/dart_frog.dart';

import '../lib/shared_handler.dart';

// Assignment-form handler: `onRequest` is bound to a shared `Handler`
// rather than declared as a function. The reference must still surface
// as the route's callee.
Handler onRequest = sharedHandler;
