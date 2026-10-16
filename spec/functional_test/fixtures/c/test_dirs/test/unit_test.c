#include "mongoose.h"

// Handler a unit test drives against a local listener; the app never serves it.
static void fake_fn(struct mg_connection *c, int ev, void *ev_data) {
  if (ev == MG_EV_HTTP_MSG) {
    struct mg_http_message *hm = (struct mg_http_message *) ev_data;
    if (mg_match(hm->uri, mg_str("/fake/mongoose"), NULL)) {
      mg_http_reply(c, 200, "", "fake\n");
    }
  }
}
