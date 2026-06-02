import 'package:serverpod/serverpod.dart';

// `WidgetRoute` renders a page on GET. No explicit `methods:` set, so it
// defaults to GET.
class RootRoute extends WidgetRoute {
  @override
  Future<AbstractWidget> build(Session session, Request request) async {
    final widget = HomePageWidget();
    return widget;
  }
}
