// A Flutter client's UI navigation file that happens to live under a
// `routes/` directory in a full-stack monorepo. It exports a widget, not
// a Dart Frog `onRequest` handler, so it must NOT be reported as an HTTP
// endpoint.
import 'package:flutter/material.dart';

class DashboardRoute extends StatelessWidget {
  const DashboardRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Dashboard')));
  }
}
