import 'package:get_server/get_server.dart';

import 'routes.dart';
import 'pages.dart';

void main() {
  runApp(
    GetServer(
      getPages: [
        // `name:` references a `static const` path declared in another file.
        GetPage(name: Routes.HOME, page: () => HomePage(), method: Method.get),
        // No `method:` → `Method.dynamic`, which matches every verb.
        GetPage(name: Routes.USER, page: () => UserPage()),
        // Explicit verb.
        GetPage(name: Routes.UPLOAD, page: () => UploadPage(), method: Method.post),
        // WebSocket upgrade → surfaced as GET.
        GetPage(name: Routes.SOCKET, page: () => SocketPage(), method: Method.ws),
        // `name:` as a plain string literal.
        GetPage(name: '/health', page: () => HealthPage(), method: Method.get),
        // Resolves the inter-constant interpolation `'$API/items'` → `/api/items`.
        GetPage(name: Routes.ITEMS, page: () => ItemsPage(), method: Method.get),
      ],
      port: 8080,
    ),
  );
}
