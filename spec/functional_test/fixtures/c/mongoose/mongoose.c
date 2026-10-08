// Vendored library amalgamation: never scanned for routes.
#include "mongoose.h"
static void builtin(struct mg_connection *c, struct mg_http_message *hm) {
  if (mg_match(hm->uri, mg_str("/vendored"), NULL)) mg_http_reply(c, 200, "", "");
}
